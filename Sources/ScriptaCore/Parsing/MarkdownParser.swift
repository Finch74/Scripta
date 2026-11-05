import Foundation

/// Line-based Markdown parser tailored for prose writing (headings, quotes, lists, code, rules).
public enum MarkdownParser {
    public static let commentRegex = try! NSRegularExpression(pattern: #"<!--[\s\S]*?(?:-->|\z)"#)
    private static let headingRegex = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let ruleRegex = try! NSRegularExpression(pattern: #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static let pageBreakRegex = try! NSRegularExpression(pattern: #"^ {0,3}={3,}[ \t]*$"#)
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^ {0,3}>[ \t]?"#)
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+])[ \t]+"#)
    private static let orderedRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(\d{1,9})[.)][ \t]+"#)
    private static let fenceRegex = try! NSRegularExpression(pattern: #"^ {0,3}(```|~~~)"#)

    public static func parse(_ ns: NSString) -> [ScriptLine] {
        let raw = TextLines.split(ns)
        let comments = TextLines.matches(commentRegex, in: ns)
        var lines: [ScriptLine] = []
        lines.reserveCapacity(raw.count)
        var fence: String?
        var previousKind: LineKind = .empty

        for (range, full) in raw {
            var line = ScriptLine(kind: .paragraph, range: range, fullRange: full, textRange: TextLines.trimmed(ns, range))
            let str = ns as String

            if let open = fence {
                if let m = fenceRegex.firstMatch(in: str, range: range), ns.substring(with: m.range(at: 1)) == open {
                    line.kind = .codeFence
                    line.markers = [range]
                    fence = nil
                } else {
                    line.kind = .code
                    line.textRange = range
                }
            } else if let m = fenceRegex.firstMatch(in: str, range: range) {
                fence = ns.substring(with: m.range(at: 1))
                line.kind = .codeFence
                line.markers = [range]
            } else if line.textRange.length == 0 {
                line.kind = .empty
            } else if comments.contains(where: { line.textRange.isContained(in: $0) }) {
                line.kind = .boneyard
            } else if GraphicNovel.detectPage(ns, in: &line) {
                // Page marker of a graphic-novel script.
            } else if GraphicNovel.detectPanel(ns, in: &line) || GraphicNovel.detectBalloon(ns, in: &line) {
                // Panel (".Vig. 1") or balloon ("**NOME**: testo") of a graphic-novel script.
            } else if let m = headingRegex.firstMatch(in: str, range: range) {
                line.kind = .heading(level: m.range(at: 1).length)
                markPrefix(m.range, of: &line, ns)
            } else if ruleRegex.firstMatch(in: str, range: range) != nil {
                line.kind = .rule
                line.markers = [range]
            } else if previousKind == .empty, pageBreakRegex.firstMatch(in: str, range: range) != nil {
                line.kind = .pageBreak
                line.markers = [range]
            } else if let m = quoteRegex.firstMatch(in: str, range: range) {
                line.kind = .blockquote
                markPrefix(m.range, of: &line, ns)
            } else if let m = bulletRegex.firstMatch(in: str, range: range) {
                line.kind = .bullet(indent: indentLevel(ns, m.range(at: 1)))
                markPrefix(m.range, of: &line, ns, markerRange: m.range(at: 2))
            } else if let m = orderedRegex.firstMatch(in: str, range: range) {
                let number = Int(ns.substring(with: m.range(at: 2))) ?? 1
                line.kind = .ordered(indent: indentLevel(ns, m.range(at: 1)), number: number)
                markPrefix(m.range, of: &line, ns,
                           markerRange: NSRange(location: m.range(at: 2).location,
                                                length: NSMaxRange(m.range) - m.range(at: 2).location))
            }

            previousKind = line.kind
            lines.append(line)
        }
        return lines
    }

    private static func markPrefix(_ prefix: NSRange, of line: inout ScriptLine, _ ns: NSString, markerRange: NSRange? = nil) {
        line.markers = [markerRange ?? prefix]
        line.textRange = TextLines.trimmed(ns, NSRange(location: NSMaxRange(prefix),
                                                       length: NSMaxRange(line.range) - NSMaxRange(prefix)))
    }

    private static func indentLevel(_ ns: NSString, _ range: NSRange) -> Int {
        var columns = 0
        for i in 0..<range.length {
            columns += ns.character(at: range.location + i) == 0x09 ? 4 : 1
        }
        return columns / 2
    }
}
