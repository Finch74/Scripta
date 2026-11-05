import Foundation

/// A navigable entry of the document index: a Fountain scene/section or a Markdown heading.
public struct OutlineItem: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case scene(number: Int)
        case section
        case heading
        case page
        case panel
    }

    public var kind: Kind
    public var title: String
    /// Nesting depth used for indentation (0 = top level).
    public var level: Int
    /// UTF-16 offset of the start of the line in the source text.
    public var location: Int

    public var id: Int { location }
}

/// Extracts the index of a document by reusing the same line classification as the editor,
/// so the sidebar always agrees with what the syntax highlighter shows.
public enum DocumentOutline {
    public static func items(in text: String, mode: DocumentMode) -> [OutlineItem] {
        let ns = text as NSString
        let lines = mode == .screenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns)
        var items: [OutlineItem] = []
        var sceneCount = 0
        // Scenes nest under the deepest Fountain section that precedes them.
        var sectionDepth = 0
        // Panels nest under the graphic-novel page that precedes them.
        var inPage = false

        for line in lines {
            let title = ns.substring(with: line.textRange).trimmingCharacters(in: .whitespaces)
            let location = line.range.location
            switch line.kind {
            case .sceneHeading:
                sceneCount += 1
                items.append(OutlineItem(kind: .scene(number: sceneCount), title: title.uppercased(),
                                         level: sectionDepth, location: location))
            case .section(let level):
                guard !title.isEmpty else { continue }
                sectionDepth = level
                inPage = false
                items.append(OutlineItem(kind: .section, title: title, level: level - 1, location: location))
            case .heading(let level):
                guard !title.isEmpty else { continue }
                items.append(OutlineItem(kind: .heading, title: title, level: level - 1, location: location))
            case .graphicNovelPage:
                sectionDepth = 0
                inPage = true
                items.append(OutlineItem(kind: .page, title: title, level: 0, location: location))
            case .panel:
                items.append(OutlineItem(kind: .panel, title: title, level: inPage ? 1 : sectionDepth, location: location))
            default:
                continue
            }
        }
        return items
    }
}
