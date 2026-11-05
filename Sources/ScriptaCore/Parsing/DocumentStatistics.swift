import Foundation

extension DocumentMode {
    /// Fountain extensions are screenplays, Markdown extensions are prose,
    /// anything else is sniffed from the content.
    public static func inferred(fromExtension ext: String, text: String) -> DocumentMode {
        switch ext.lowercased() {
        case "fountain", "spmd": .screenplay
        case "md", "markdown", "mdown", "mkd": .prose
        default: FountainParser.looksLikeScreenplay(text) ? .screenplay : .prose
        }
    }
}

/// Counts, outline and cast of a document, shared by every front end (CLI, Linux GUI).
public struct DocumentStatistics: Sendable {
    public let mode: DocumentMode
    /// The `Title:` field of the Fountain title page, without emphasis markers.
    public let title: String?
    /// Words of the printable text only: comments, notes, title-page fields and code are left out.
    public let words: Int
    public let characterCount: Int
    public let nonEmptyLines: Int
    public let dialogueLines: Int
    public let scenes: Int
    public let sections: Int
    public let headings: Int
    public let pages: Int
    public let panels: Int
    public let outline: [OutlineItem]
    public let cast: [CharacterStat]

    public init(text: String, mode: DocumentMode) {
        let ns = text as NSString
        let lines = mode == .screenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns)
        let outline = DocumentOutline.items(in: text, mode: mode)

        self.mode = mode
        self.outline = outline
        cast = CharacterAnalysis.statistics(text: text, mode: mode)
        characterCount = text.count
        words = lines.reduce(0) { total, line in
            switch line.kind {
            case .empty, .boneyard, .note, .titleField, .codeFence, .code, .pageBreak, .rule: total
            default: total + TextLines.wordCount(ns, in: line.textRange)
            }
        }
        nonEmptyLines = lines.filter { $0.kind != .empty }.count
        dialogueLines = lines.filter { $0.kind == .dialogue || $0.kind == .balloon }.count
        title = lines.first { $0.kind == .titleField(key: "title") }
            .map { ns.substring(with: $0.textRange).replacingOccurrences(of: "*", with: "") }

        func count(_ kind: (OutlineItem.Kind) -> Bool) -> Int { outline.filter { kind($0.kind) }.count }
        scenes = count { if case .scene = $0 { true } else { false } }
        sections = count { $0 == .section }
        headings = count { $0 == .heading }
        pages = count { $0 == .page }
        panels = count { $0 == .panel }
    }

    public var speeches: Int { cast.reduce(0) { $0 + $1.speeches } }

    /// Estimated at 230 words per minute, never less than one minute.
    public var readingMinutes: Int { max(1, Int((Double(words) / 230).rounded())) }

    /// Share of the printable words spoken by a character, in percent.
    public func share(of stat: CharacterStat) -> Double {
        words > 0 ? Double(stat.words) / Double(words) * 100 : 0
    }
}
