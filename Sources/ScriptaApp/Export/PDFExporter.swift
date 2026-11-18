import AppKit
import CoreText
import PDFKit
import WebKit
import ScriptaCore

/// Renders HTML into a paginated PDF through WebKit's print engine, then stamps page numbers
/// and metadata with Core Graphics / PDFKit.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var window: NSWindow?

    func export(html: String, to destination: URL, layout: PageLayout,
                numbering: PageNumbering, metadata: PDFMetadata) async throws {
        let frame = NSRect(x: 0, y: 0, width: layout.contentSize.width + layout.gutterLeft + layout.gutterRight,
                           height: layout.contentSize.height)
        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        webView.appearance = NSAppearance(named: .aqua)

        // WebKit needs to live in a window to lay out; keep it off-screen and invisible.
        let window = NSWindow(contentRect: frame.offsetBy(dx: -30_000, dy: -30_000),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = webView
        self.window = window
        defer {
            webView.navigationDelegate = nil
            window.contentView = nil
            window.close()
            self.window = nil
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        // Make sure web fonts and layout are settled before printing.
        _ = try? await webView.callAsyncJavaScript("await document.fonts.ready; return true;", contentWorld: .page)
        // A visible scroller would narrow the layout viewport and WebKit would then rescale the
        // printout to fit the page; grow the view to the full document height so none appears.
        if let height = try? await webView.callAsyncJavaScript(
            "return document.documentElement.scrollHeight;", contentWorld: .page) as? Double {
            webView.setFrameSize(NSSize(width: webView.frame.width, height: max(frame.height, ceil(height) + 1)))
        }

        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory.appendingPathComponent("Scripta-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDir) }
        let rawURL = workDir.appendingPathComponent("raw.pdf")
        let finalURL = workDir.appendingPathComponent("final.pdf")

        let info = NSPrintInfo()
        info.paperSize = layout.paper
        info.orientation = .portrait
        info.topMargin = layout.top
        info.bottomMargin = layout.bottom
        info.leftMargin = layout.left - layout.gutterLeft
        info.rightMargin = layout.right - layout.gutterRight
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.scalingFactor = 1
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = rawURL
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        
        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            printContinuation = continuation
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
        guard success, fileManager.fileExists(atPath: rawURL.path) else { throw ExportError.printFailed }

        try Self.finalize(source: rawURL, destination: finalURL, layout: layout, numbering: numbering, metadata: metadata)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: finalURL)
        } else {
            try fileManager.moveItem(at: finalURL, to: destination)
        }
    }

    /// AppKit may invoke this from the print operation's worker thread.
    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                                        contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.printContinuation?.resume(returning: success)
                self.printContinuation = nil
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: ExportError.loadFailed(error.localizedDescription))
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: ExportError.loadFailed(error.localizedDescription))
        loadContinuation = nil
    }

    // MARK: - Post-processing

    /// Re-draws every page into a new PDF, adding page numbers and document metadata.
    private static func finalize(source: URL, destination: URL, layout: PageLayout,
                                 numbering: PageNumbering, metadata: PDFMetadata) throws {
        guard let document = PDFDocument(url: source), document.pageCount > 0 else {
            throw ExportError.postProcessingFailed
        }
        var info: [CFString: Any] = [
            kCGPDFContextCreator: "Scripta",
            kCGPDFContextTitle: metadata.title
        ]
        if let author = metadata.author { info[kCGPDFContextAuthor] = author }

        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, info as CFDictionary) else {
            throw ExportError.postProcessingFailed
        }

        let fontName: String
        let fontSize: CGFloat
        switch numbering {
        case .screenplay:
            fontName = NSFont(name: "CourierPrime", size: 12) != nil ? "CourierPrime" : "CourierNewPSMT"
            fontSize = 12
        default:
            fontName = NSFont(name: "IowanOldStyle-Roman", size: 10) != nil ? "IowanOldStyle-Roman" : "Georgia"
            fontSize = 10
        }
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var box = page.bounds(for: .mediaBox)
            context.beginPage(mediaBox: &box)
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            let label = numbering.label(forPageAt: index)

            if let label {
                let attributed = NSAttributedString(string: label, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
                ])
                let line = CTLineCreateWithAttributedString(attributed)
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                let position: CGPoint
                switch numbering {
                case .screenplay:
                    position = CGPoint(x: box.maxX - layout.right - width, y: box.maxY - 36 - fontSize * 0.8)
                default:
                    position = CGPoint(x: box.midX - width / 2, y: box.minY + 36)
                }
                context.textMatrix = .identity
                context.textPosition = position
                CTLineDraw(line, context)
            }
            context.endPage()
        }
        context.closePDF()
    }
}
