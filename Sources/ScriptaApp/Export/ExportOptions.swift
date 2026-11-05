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

enum PaperSize: String, CaseIterable, Identifiable, Sendable {
    case letter, a4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .letter: "US Letter"
        case .a4: "A4"
        }
    }

    /// Size in PostScript points.
    var size: CGSize {
        switch self {
        case .letter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.28, height: 841.89)
        }
    }

    var cssName: String {
        switch self {
        case .letter: "letter"
        case .a4: "A4"
        }
    }
}

struct ExportOptions: Equatable, Sendable {
    var paper: PaperSize
    var includeNotes = false
    var includeSceneNumbers = true
    var includeTitlePage = true

    static func defaults(for mode: DocumentMode) -> ExportOptions {
        ExportOptions(paper: mode == .screenplay ? .letter : .a4)
    }
}

/// Physical page geometry, in points.
struct PageLayout: Sendable {
    var paper: CGSize
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat
    /// Part of the left/right margin handed to WebKit as printable area (and filled with CSS padding),
    /// so that elements living in the margin — such as scene numbers — are not clipped.
    var gutterLeft: CGFloat = 0
    var gutterRight: CGFloat = 0

    var contentSize: CGSize {
        CGSize(width: paper.width - left - right, height: paper.height - top - bottom)
    }

    static func layout(for mode: DocumentMode, paper: PaperSize) -> PageLayout {
        switch mode {
        case .screenplay:
            // Industry standard: 1.5" binding margin, 1" elsewhere.
            PageLayout(paper: paper.size, top: 72, left: 108, bottom: 72, right: 72, gutterLeft: 54, gutterRight: 36)
        case .prose:
            PageLayout(paper: paper.size, top: 72, left: 72, bottom: 72, right: 72)
        }
    }
}
