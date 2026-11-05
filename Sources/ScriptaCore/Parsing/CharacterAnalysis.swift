import Foundation

/// One speech: a screenplay cue plus its parentheticals and dialogue, or a single comic balloon.
public struct Speech: Sendable {
    public let name: String
    /// From the start of the cue to the end of the last dialogue line.
    public let range: NSRange
    /// Printable text of each line (cue, parentheticals, dialogue), used for highlighting.
    public let textRanges: [NSRange]
    public let words: Int
}

/// Per-character totals.
public struct CharacterStat: Identifiable, Sendable {
    public let name: String
    public var speeches = 0
    public var words = 0

    public var id: String { name }
}

/// Recognises the characters of a screenplay or graphic-novel script and measures how much each one speaks.
public enum CharacterAnalysis {
    /// Canonical name of a cue: extensions such as `(V.O.)` / `(CONT'D)` and the dual-dialogue `^` removed.
    public static func normalizedName(_ cue: String) -> String {
        var name = cue
        if name.hasPrefix("@") { name.removeFirst() }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        name = name.replacingOccurrences(of: "^", with: "")
        return name.trimmingCharacters(in: .whitespaces).uppercased()
    }

    public static func speeches(in ns: NSString, mode: DocumentMode) -> [Speech] {
        speeches(in: mode == .screenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns), ns: ns)
    }

    public static func speeches(in lines: [ScriptLine], ns: NSString) -> [Speech] {
        var result: [Speech] = []
        var current: (name: String, start: Int, end: Int, words: Int, lines: [NSRange])?

        func close() {
            if let c = current, !c.name.isEmpty {
                result.append(Speech(name: c.name, range: NSRange(location: c.start, length: c.end - c.start),
                                     textRanges: c.lines, words: c.words))
            }
            current = nil
        }

        for line in lines {
            switch line.kind {
            case .character:
                close()
                current = (normalizedName(ns.substring(with: line.textRange)), line.range.location, NSMaxRange(line.range), 0,
                           [TextLines.trimmed(ns, line.range)])
            case .dialogue where current != nil:
                current!.end = NSMaxRange(line.range)
                current!.words += wordCount(ns, line.textRange)
                current!.lines.append(line.textRange)
            case .parenthetical where current != nil:
                current!.end = NSMaxRange(line.range)
                current!.lines.append(line.textRange)
            case .balloon:
                close()
                guard let parts = GraphicNovel.balloonParts(ns, line.range) else { continue }
                let name = normalizedName(ns.substring(with: parts.name))
                guard !name.isEmpty else { continue }
                result.append(Speech(name: name, range: line.range, textRanges: [line.textRange],
                                     words: wordCount(ns, parts.speech)))
            default:
                close()
            }
        }
        close()
        return result
    }

    /// Totals per character, most talkative first.
    public static func statistics(text: String, mode: DocumentMode) -> [CharacterStat] {
        var byName: [String: CharacterStat] = [:]
        for speech in speeches(in: text as NSString, mode: mode) {
            byName[speech.name, default: CharacterStat(name: speech.name)].speeches += 1
            byName[speech.name]!.words += speech.words
        }
        return byName.values.sorted { ($0.words, $1.name) > ($1.words, $0.name) }
    }

    private static func wordCount(_ ns: NSString, _ range: NSRange) -> Int {
        TextLines.wordCount(ns, in: range)
    }
}
