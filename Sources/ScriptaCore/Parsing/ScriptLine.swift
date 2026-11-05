import Foundation

/// The two writing modes supported by Scripta, mirroring Highland 2.
public enum DocumentMode: String, CaseIterable, Identifiable, Sendable {
    /// Fountain screenplay syntax.
    case screenplay
    /// Markdown prose (novels, articles, manuscripts).
    case prose

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .screenplay: "Sceneggiatura"
        case .prose: "Prosa"
        }
    }
}

/// Block-level classification of a single line of source text.
public enum LineKind: Equatable, Sendable {
    case empty

    // Fountain
    case titleField(key: String)
    case sceneHeading(sceneNumber: String?)
    case action
    case character(dual: Bool)
    case parenthetical
    case dialogue
    case transition
    case centered
    case lyrics
    case section(level: Int)
    case synopsis
    case pageBreak
    case boneyard
    case note

    // Markdown
    case heading(level: Int)
    case paragraph
    case blockquote
    case bullet(indent: Int)
    case ordered(indent: Int, number: Int)
    case codeFence
    case code
    case rule

    // Graphic novel (both modes)
    /// A page marker of a graphic-novel script ("# Tav. 1", "# Page 1"), printed as a bold heading.
    case graphicNovelPage
    /// A panel of a graphic-novel page (".Vig. 1", ".PANEL 1").
    case panel
    /// A comic balloon: name and speech on one line ("**NOME (f.c.)**: testo").
    case balloon

    /// Whether inline emphasis (bold, italic…) should be parsed inside the line.
    public var allowsInlineMarkup: Bool {
        switch self {
        case .empty, .pageBreak, .boneyard, .codeFence, .code, .rule:
            false
        default:
            true
        }
    }
}

/// A classified line with the UTF-16 ranges needed both for on-screen styling and for export.
public struct ScriptLine: Equatable, Sendable {
    public var kind: LineKind
    /// The line content, without the line terminator.
    public var range: NSRange
    /// The line including its terminator (used for paragraph attributes).
    public var fullRange: NSRange
    /// The printable portion of the line (syntax markers such as `@`, `.`, `#` removed).
    public var textRange: NSRange
    /// Syntax markers that should be dimmed in the editor and dropped on export.
    public var markers: [NSRange] = []
}

public enum GraphicNovel {
    /// `# Tav`, `# Tav.`, `# Tav 3`, `# Tavola 3`, `# Page 3`, `# Pagina 3`… The capture is the `#` prefix
    /// to dim and drop. "Page"/"Pagina" need a number, so a heading such as "# Pagina bianca" stays a heading.
    private static let pageRegex = try! NSRegularExpression(
        pattern: #"^([ \t]{0,3}#[ \t]*)(?:Tav(?:ola)?(?!\p{L})|Pag(?:e|ina)\.?[ \t]*\d)"#, options: [.caseInsensitive])

    /// `.Vig. 1`, `.Vig.1`, `.Vignetta 1`, `.PANEL 1`… The capture is the leading `.` to dim and drop.
    private static let panelRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(\.)[ \t]*(?:Vig(?:netta)?|Panel)(?!\p{L})"#, options: [.caseInsensitive])

    /// `**NOME**: testo`, `**NOME (f.c.)**: testo`, `**NOME:** testo`.
    /// Captures: 1 = name (with extensions), 2 = speech.
    private static let balloonRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*\*\*([^*\n]*?\p{L}[^*\n]*?)(?::\*\*|\*\*[ \t]*:)[ \t]*(.*)$"#)

    /// Classifies `line` as a panel marker when it starts with `.Vig` or `.PANEL`.
    public static func detectPanel(_ ns: NSString, in line: inout ScriptLine) -> Bool {
        guard let m = panelRegex.firstMatch(in: ns as String, range: line.range) else { return false }
        let dot = m.range(at: 1)
        line.kind = .panel
        line.markers = [dot]
        line.textRange = TextLines.trimmed(ns, NSRange(location: NSMaxRange(dot), length: NSMaxRange(line.range) - NSMaxRange(dot)))
        return true
    }

    /// Classifies `line` as a balloon when it reads `**NAME**: speech`. The bold markers are kept in
    /// the text so the inline parser renders the name in bold, in the editor and on export.
    public static func detectBalloon(_ ns: NSString, in line: inout ScriptLine) -> Bool {
        guard balloonParts(ns, line.range) != nil else { return false }
        line.kind = .balloon
        return true
    }

    /// Name and speech ranges of a balloon line.
    public static func balloonParts(_ ns: NSString, _ range: NSRange) -> (name: NSRange, speech: NSRange)? {
        guard let m = balloonRegex.firstMatch(in: ns as String, range: range) else { return nil }
        return (m.range(at: 1), m.range(at: 2))
    }

    /// Classifies `line` as a graphic-novel page marker when it starts with `# Tav` or `# Page N`.
    public static func detectPage(_ ns: NSString, in line: inout ScriptLine) -> Bool {
        guard let m = pageRegex.firstMatch(in: ns as String, range: line.range) else { return false }
        let prefix = m.range(at: 1)
        line.kind = .graphicNovelPage
        line.markers = [TextLines.trimmed(ns, prefix)]
        line.textRange = TextLines.trimmed(ns, NSRange(location: NSMaxRange(prefix),
                                                       length: NSMaxRange(line.range) - NSMaxRange(prefix)))
        return true
    }
}

public enum TextLines {
    /// Splits text into line ranges. A trailing empty line is reported when the text is empty
    /// or ends with a line terminator, so that the caret line always has a classification.
    public static func split(_ ns: NSString) -> [(range: NSRange, full: NSRange)] {
        var result: [(NSRange, NSRange)] = []
        let length = ns.length
        var location = 0
        while location < length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            result.append((NSRange(location: start, length: contentsEnd - start),
                           NSRange(location: start, length: end - start)))
            location = end
        }
        if length == 0 || CharacterSet.newlines.contains(UnicodeScalar(ns.character(at: length - 1)) ?? " ") {
            result.append((NSRange(location: length, length: 0), NSRange(location: length, length: 0)))
        }
        return result
    }

    /// Number of leading whitespace UTF-16 units in `ns` within `range`.
    public static func leadingWhitespace(_ ns: NSString, in range: NSRange) -> Int {
        var count = 0
        while count < range.length {
            let c = ns.character(at: range.location + count)
            guard c == 0x20 || c == 0x09 else { break }
            count += 1
        }
        return count
    }

    /// Number of trailing whitespace UTF-16 units in `ns` within `range`.
    public static func trailingWhitespace(_ ns: NSString, in range: NSRange) -> Int {
        var count = 0
        while count < range.length {
            let c = ns.character(at: NSMaxRange(range) - 1 - count)
            guard c == 0x20 || c == 0x09 else { break }
            count += 1
        }
        return count
    }

    /// The range trimmed of surrounding spaces and tabs.
    public static func trimmed(_ ns: NSString, _ range: NSRange) -> NSRange {
        let lead = leadingWhitespace(ns, in: range)
        let rest = NSRange(location: range.location + lead, length: range.length - lead)
        let trail = trailingWhitespace(ns, in: rest)
        return NSRange(location: rest.location, length: rest.length - trail)
    }

    /// Number of words in `ns` within `range`.
    public static func wordCount(_ ns: NSString, in range: NSRange) -> Int {
        #if canImport(Darwin)
        var count = 0
        ns.enumerateSubstrings(in: range, options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
        #else
        // swift-corelibs-foundation does not implement word enumeration: split on anything that is
        // neither a letter nor a digit, keeping apostrophes inside words ("l'ultima" counts once).
        var count = 0
        var inWord = false
        for scalar in ns.substring(with: range).unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { count += 1 }
                inWord = true
            } else if !(inWord && (scalar == "'" || scalar == "\u{2019}")) {
                inWord = false
            }
        }
        return count
        #endif
    }

    /// Ranges of all matches of `regex` in the whole string.
    public static func matches(_ regex: NSRegularExpression, in ns: NSString) -> [NSRange] {
        regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }
}

extension NSRange {
    /// True when `self` is non-empty and lies completely within `other`.
    public func isContained(in other: NSRange) -> Bool {
        length > 0 && location >= other.location && NSMaxRange(self) <= NSMaxRange(other)
    }

    public func shifted(by delta: Int) -> NSRange {
        NSRange(location: location + delta, length: length)
    }
}
