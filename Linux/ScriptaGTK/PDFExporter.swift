import CGtk
import CPoppler
import CWebKit
import Foundation
import ScriptaCore

/// Linux counterpart of the macOS `PDFExporter`: renders HTML into a paginated PDF through
/// WebKitGTK's print engine, then re-draws the pages with Poppler + cairo to stamp page numbers
/// and metadata.
///
/// Everything runs on the GLib main loop; `completion` is called exactly once, with `nil` on success.
@MainActor
final class PDFExporter {
    private let html: String
    private let destination: URL
    private let layout: PageLayout
    private let numbering: PageNumbering
    private let metadata: PDFMetadata
    private let completion: @MainActor (Error?) -> Void

    private let workDir: URL
    private var rawURL: URL { workDir.appendingPathComponent("raw.pdf") }
    private var finalURL: URL { workDir.appendingPathComponent("final.pdf") }

    private var webView: Object?
    private var operation: Object?
    private var finished = false

    /// Exporters in flight; each one keeps itself alive until it calls its completion.
    private static var active: [ObjectIdentifier: PDFExporter] = [:]

    static func export(html: String, to destination: URL, layout: PageLayout, numbering: PageNumbering,
                       metadata: PDFMetadata, completion: @escaping @MainActor (Error?) -> Void) {
        let exporter = PDFExporter(html: html, destination: destination, layout: layout, numbering: numbering,
                                   metadata: metadata, completion: completion)
        active[ObjectIdentifier(exporter)] = exporter
        exporter.start()
    }

    private init(html: String, destination: URL, layout: PageLayout, numbering: PageNumbering,
                 metadata: PDFMetadata, completion: @escaping @MainActor (Error?) -> Void) {
        self.html = html
        self.destination = destination
        self.layout = layout
        self.numbering = numbering
        self.metadata = metadata
        self.completion = completion
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scripta-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Pipeline

    private func start() {
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            return finish(error)
        }
        // A GtkWidget starts floating: sink it so this object owns the reference.
        let webView = g_object_ref_sink(raw(webkit_web_view_new()))!
        self.webView = webView
        connect(webView, "load-changed") { [self] (event: Int32) in
            if event == Int32(WEBKIT_LOAD_FINISHED.rawValue) { startPrinting() }
        }
        connectLoadFailed(webView) { [self] message in finish(ExportError.loadFailed(message)) }
        webkit_web_view_load_html(cast(webView), html, nil)
    }

    private func startPrinting() {
        guard !finished, let webView else { return }

        let paper = gtk_paper_size_new_custom("scripta", "Scripta", layout.paper.width, layout.paper.height,
                                              GTK_UNIT_POINTS)
        let pageSetup = raw(gtk_page_setup_new())!
        gtk_page_setup_set_paper_size(cast(pageSetup), paper)
        gtk_paper_size_free(paper)
        gtk_page_setup_set_orientation(cast(pageSetup), GTK_PAGE_ORIENTATION_PORTRAIT)
        gtk_page_setup_set_top_margin(cast(pageSetup), layout.top, GTK_UNIT_POINTS)
        gtk_page_setup_set_bottom_margin(cast(pageSetup), layout.bottom, GTK_UNIT_POINTS)
        // As on macOS, the gutters are printable area filled with CSS padding (scene numbers live there).
        gtk_page_setup_set_left_margin(cast(pageSetup), layout.left - layout.gutterLeft, GTK_UNIT_POINTS)
        gtk_page_setup_set_right_margin(cast(pageSetup), layout.right - layout.gutterRight, GTK_UNIT_POINTS)

        let settings = raw(gtk_print_settings_new())!
        gtk_print_settings_set_printer(cast(settings), "Print to File")
        gtk_print_settings_set(cast(settings), GTK_PRINT_SETTINGS_OUTPUT_FILE_FORMAT, "pdf")
        gtk_print_settings_set(cast(settings), GTK_PRINT_SETTINGS_OUTPUT_URI, rawURL.absoluteString)
        gtk_print_settings_set_orientation(cast(settings), GTK_PAGE_ORIENTATION_PORTRAIT)
        gtk_print_settings_set_scale(cast(settings), 100)

        let operation = raw(webkit_print_operation_new(cast(webView)))!
        self.operation = operation
        webkit_print_operation_set_page_setup(cast(operation), cast(pageSetup))
        webkit_print_operation_set_print_settings(cast(operation), cast(settings))
        g_object_unref(pageSetup)
        g_object_unref(settings)

        connect(operation, "failed") { [self] (error: Object?) in
            let message = error.flatMap { $0.assumingMemoryBound(to: GError.self).pointee.message }
                .map { String(cString: $0) }
            finish(message.map(ExportError.loadFailed) ?? ExportError.printFailed)
        }
        connect(operation, "finished") { [self] in
            // "failed" is emitted before "finished": in that case we are already done.
            guard !finished else { return }
            do {
                guard FileManager.default.fileExists(atPath: rawURL.path) else { throw ExportError.printFailed }
                try Self.finalize(source: rawURL, destination: finalURL, layout: layout,
                                  numbering: numbering, metadata: metadata)
                try Self.move(finalURL, to: destination)
                finish(nil)
            } catch {
                finish(error)
            }
        }
        webkit_print_operation_print(cast(operation))
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        completion(error)
        // Tear down outside the signal emission that brought us here.
        _ = after(milliseconds: 0) { [self] in
            if let operation { g_object_unref(operation) }
            if let webView { g_object_unref(webView) }
            operation = nil
            webView = nil
            try? FileManager.default.removeItem(at: workDir)
            // WebKit adds every print-to-file output to the recent files: drop the temporary PDF.
            gtk_recent_manager_remove_item(gtk_recent_manager_get_default(), rawURL.absoluteString, nil)
            Self.active[ObjectIdentifier(self)] = nil
        }
    }

    private static func move(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
    }

    // MARK: - Post-processing

    /// Re-draws every page into a new PDF, adding page numbers and document metadata.
    private static func finalize(source: URL, destination: URL, layout: PageLayout,
                                 numbering: PageNumbering, metadata: PDFMetadata) throws {
        var error: UnsafeMutablePointer<GError>?
        guard let document = poppler_document_new_from_file(source.absoluteString, nil, &error) else {
            if let error { g_error_free(error) }
            throw ExportError.postProcessingFailed
        }
        defer { g_object_unref(raw(document)) }
        let pageCount = poppler_document_get_n_pages(document)
        guard pageCount > 0 else { throw ExportError.postProcessingFailed }

        guard let surface = cairo_pdf_surface_create(destination.path, layout.paper.width, layout.paper.height),
              cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else {
            throw ExportError.postProcessingFailed
        }
        cairo_pdf_surface_set_metadata(surface, CAIRO_PDF_METADATA_CREATOR, "Scripta")
        cairo_pdf_surface_set_metadata(surface, CAIRO_PDF_METADATA_TITLE, metadata.title)
        if let author = metadata.author { cairo_pdf_surface_set_metadata(surface, CAIRO_PDF_METADATA_AUTHOR, author) }

        let fontSize: Double
        let font: String
        switch numbering {
        case .screenplay:
            fontSize = 12
            font = "Courier Prime, Courier Final Draft, Courier New, Courier, monospace \(Int(fontSize))"
        default:
            fontSize = 10
            font = "Iowan Old Style, Charter, Georgia, Times New Roman, serif \(Int(fontSize))"
        }
        let fontDescription = pango_font_description_from_string(font)
        defer { pango_font_description_free(fontDescription) }

        for index in 0..<pageCount {
            guard let page = poppler_document_get_page(document, index) else { continue }
            defer { g_object_unref(raw(page)) }
            var width = 0.0, height = 0.0
            poppler_page_get_size(page, &width, &height)
            cairo_pdf_surface_set_size(surface, width, height)

            let context = cairo_create(surface)
            defer { cairo_destroy(context) }
            cairo_save(context)
            poppler_page_render_for_printing(page, context)
            cairo_restore(context)

            if let label = numbering.label(forPageAt: Int(index)) {
                let text = pango_cairo_create_layout(context)!
                defer { g_object_unref(raw(text)) }
                // cairo PDF units are points: lay the text out at 72 dpi so that 12pt means 12 units.
                pango_cairo_context_set_resolution(pango_layout_get_context(text), 72)
                pango_layout_context_changed(text)
                pango_layout_set_font_description(text, fontDescription)
                pango_layout_set_text(text, label, -1)
                var textWidth: Int32 = 0, textHeight: Int32 = 0
                pango_layout_get_size(text, &textWidth, &textHeight)
                let pangoScale = Double(PANGO_SCALE)
                let labelWidth = Double(textWidth) / pangoScale
                let ascent = Double(pango_layout_get_baseline(text)) / pangoScale

                // Same baselines as the macOS exporter (which measures from the bottom of the page).
                let x: Double, baseline: Double
                switch numbering {
                case .screenplay:
                    x = width - layout.right - labelWidth
                    baseline = 36 + fontSize * 0.8
                default:
                    x = (width - labelWidth) / 2
                    baseline = height - 36
                }
                cairo_set_source_rgb(context, 0, 0, 0)
                cairo_move_to(context, x, baseline - ascent)
                pango_cairo_show_layout(context, text)
            }
            cairo_show_page(context)
        }
        cairo_surface_finish(surface)
        let status = cairo_surface_status(surface)
        cairo_surface_destroy(surface)
        guard status == CAIRO_STATUS_SUCCESS else { throw ExportError.postProcessingFailed }
    }
}

/// WebKitWebView's "load-failed": `gboolean handler(WebKitWebView *, WebKitLoadEvent, gchar *uri, GError *, gpointer)`.
@MainActor
private func connectLoadFailed(_ webView: Object, _ handler: @escaping @MainActor (String) -> Void) {
    final class Box: @unchecked Sendable {
        let handler: @MainActor (String) -> Void
        init(_ handler: @escaping @MainActor (String) -> Void) { self.handler = handler }
    }
    let trampoline: @convention(c) (gpointer?, gint, gpointer?, gpointer?, gpointer?) -> gboolean = { _, _, _, error, data in
        let box = Unmanaged<Box>.fromOpaque(data!).takeUnretainedValue()
        let message = error.flatMap { $0.assumingMemoryBound(to: GError.self).pointee.message }
            .map { String(cString: $0) } ?? "errore sconosciuto"
        MainActor.assumeIsolated { box.handler(message) }
        return 0
    }
    let data = Unmanaged.passRetained(Box(handler)).toOpaque()
    g_signal_connect_data(webView, "load-failed", unsafeBitCast(trampoline, to: GCallback.self), data,
                          { data, _ in data.map { Unmanaged<Box>.fromOpaque($0).release() } },
                          GConnectFlags(rawValue: 0))
}
