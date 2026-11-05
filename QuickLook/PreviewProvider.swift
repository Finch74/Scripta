import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look preview (space bar in Finder) for Fountain and Markdown files: the same formatted
/// HTML as Scripta's preview and HTML export, rendered by Quick Look's own web view.
///
/// Built by build-app.sh together with the app's parsing and export sources.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let text = DocumentText.decode(try Data(contentsOf: url))
        let mode = DocumentText.mode(forExtension: url.pathExtension, text: text)
        var options = ExportOptions.defaults(for: mode)
        options.includeNotes = true
        let html = HTMLRenderer.render(text: text, mode: mode, options: options,
                                       fallbackTitle: url.deletingPathExtension().lastPathComponent,
                                       forPrint: false).html

        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 1060)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
    }
}
