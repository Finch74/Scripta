import Foundation
import UniformTypeIdentifiers
#if canImport(ScriptaCore)
import ScriptaCore
#endif

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown, fountain, html, pdf

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .fountain: "fountain"
        case .html: "html"
        case .pdf: "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: .markdownText
        case .fountain: .fountain
        case .html: .html
        case .pdf: .pdf
        }
    }

    var menuTitle: String {
        switch self {
        case .markdown: "Markdown (.md)…"
        case .fountain: "Fountain (.fountain)…"
        case .html: "HTML (.html)…"
        case .pdf: "PDF (.pdf)…"
        }
    }

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "fountain", "spmd": self = .fountain
        case "html", "htm": self = .html
        case "pdf": self = .pdf
        default: return nil
        }
    }
}
