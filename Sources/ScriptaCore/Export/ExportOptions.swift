import Foundation

// Platform-independent export settings, shared by the macOS app (WebKit/PDFKit), the GTK front end
// (WebKitGTK/Poppler) and the Quick Look extension (built from the same sources as a single module).

public enum PaperSize: String, CaseIterable, Identifiable, Sendable {
    case letter, a4

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .letter: "US Letter"
        case .a4: "A4"
        }
    }

    /// Size in PostScript points.
    public var size: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        }
    }

    public var cssName: String {
        switch self {
        case .letter: "letter"
        case .a4: "A4"
        }
    }
}

public struct ExportOptions: Equatable, Sendable {
    public var paper: PaperSize
    public var includeNotes: Bool
    public var includeSceneNumbers: Bool
    public var includeTitlePage: Bool

    public init(paper: PaperSize, includeNotes: Bool = false, includeSceneNumbers: Bool = true,
                includeTitlePage: Bool = true) {
        self.paper = paper
        self.includeNotes = includeNotes
        self.includeSceneNumbers = includeSceneNumbers
        self.includeTitlePage = includeTitlePage
    }

    public static func defaults(for mode: DocumentMode) -> ExportOptions {
        ExportOptions(paper: mode == .screenplay ? .letter : .a4)
    }
}

/// Physical page geometry, in points.
public struct PageLayout: Sendable {
    public var paper: CGSize
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    /// Part of the left/right margin handed to WebKit as printable area (and filled with CSS padding),
    /// so that elements living in the margin — such as scene numbers — are not clipped.
    public var gutterLeft: CGFloat
    public var gutterRight: CGFloat

    public init(paper: CGSize, top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat,
                gutterLeft: CGFloat = 0, gutterRight: CGFloat = 0) {
        self.paper = paper
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
        self.gutterLeft = gutterLeft
        self.gutterRight = gutterRight
    }

    public var contentSize: CGSize {
        CGSize(width: paper.width - left - right, height: paper.height - top - bottom)
    }

    public static func layout(for mode: DocumentMode, paper: PaperSize) -> PageLayout {
        switch mode {
        case .screenplay:
            // Industry standard: 1.5" binding margin, 1" elsewhere.
            PageLayout(paper: paper.size, top: 72, left: 108, bottom: 72, right: 72, gutterLeft: 54, gutterRight: 36)
        case .prose:
            PageLayout(paper: paper.size, top: 72, left: 72, bottom: 72, right: 72)
        }
    }
}

public enum PageNumbering: Sendable {
    case none
    /// Screenplay convention: "N." top-right, omitted on the first page of the script.
    case screenplay(skipLeadingPages: Int)
    /// Centred at the foot of every page.
    case footer(skipLeadingPages: Int)

    /// The usual numbering for `mode`, skipping the title page when there is one.
    public static func standard(for mode: DocumentMode, hasTitlePage: Bool) -> PageNumbering {
        let skip = hasTitlePage ? 1 : 0
        return mode == .screenplay ? .screenplay(skipLeadingPages: skip) : .footer(skipLeadingPages: skip)
    }

    /// The label printed on the page at zero-based `index`, if any.
    public func label(forPageAt index: Int) -> String? {
        switch self {
        case .none:
            return nil
        case .screenplay(let skip):
            let number = index + 1 - skip
            return number >= 2 ? "\(number)." : nil
        case .footer(let skip):
            let number = index + 1 - skip
            return number >= 1 ? "\(number)" : nil
        }
    }
}

public struct PDFMetadata: Sendable {
    public var title: String
    public var author: String?

    public init(title: String, author: String? = nil) {
        self.title = title
        self.author = author
    }
}

public enum ExportError: LocalizedError {
    case loadFailed(String)
    case printFailed
    case postProcessingFailed

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let reason): "Impossibile preparare il documento per la stampa: \(reason)"
        case .printFailed: "La generazione del PDF non è riuscita."
        case .postProcessingFailed: "Impossibile finalizzare il PDF (numerazione pagine)."
        }
    }
}
