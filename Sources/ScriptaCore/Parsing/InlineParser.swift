import Foundation

public enum InlineStyle: Equatable, Sendable {
    case bold, italic, boldItalic, underline, code, note
    case link(url: String)
}

public indirect enum InlineNode: Sendable {
    case text(NSRange)
    case styled(InlineStyle, content: NSRange, markers: [NSRange], children: [InlineNode])
}

/// Recursive parser for inline emphasis. Supports nesting (e.g. `**bold *and italic***`).
public enum InlineParser {
    private enum Rule: CaseIterable {
        case note, code, link, boldItalic, bold, italic, underscore

        /// Every pattern captures: 1 = opening marker, 2 = content, 3 = closing marker.
        var pattern: String {
            switch self {
            case .note: #"(\[\[)(.*?)(\]\])"#
            case .code: #"(`+)(.+?)(\1)"#
            case .link: #"(\[)([^\]\n]+)(\]\(([^)\s]+)\))"#
            case .boldItalic: #"(\*\*\*)(?=\S)(.+?)(?<=\S)(\*\*\*)"#
            case .bold: #"(\*\*|__)(?=[^\s_*])(.+?)(?<=[^\s_*]|\*)(\1)"#
            case .italic: #"(?<!\*)(\*)(?![\s*])(.+?)(?<![\s*])(\*)(?!\*)"#
            case .underscore: #"(?<![\p{L}\p{N}_])(_)(?![\s_])(.+?)(?<![\s_])(_)(?![\p{L}\p{N}_])"#
            }
        }
    }

    private static let regexes: [Rule: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: Rule.allCases.map { ($0, try! NSRegularExpression(pattern: $0.pattern)) })

    private static let fountainRules: [Rule] = [.note, .boldItalic, .bold, .italic, .underscore]
    private static let markdownRules: [Rule] = [.note, .code, .link, .boldItalic, .bold, .italic, .underscore]

    public static func parse(_ ns: NSString, range: NSRange, mode: DocumentMode) -> [InlineNode] {
        parse(ns, range: range, rules: mode == .screenplay ? fountainRules : markdownRules, mode: mode, depth: 0)
    }

    private static func parse(_ ns: NSString, range: NSRange, rules: [Rule], mode: DocumentMode, depth: Int) -> [InlineNode] {
        guard range.length > 0 else { return [] }
        let string = ns as String
        let end = NSMaxRange(range)
        var nodes: [InlineNode] = []
        var location = range.location
        // Cache of the next match for each rule; re-searched only once the cursor passes it.
        var cache: [Rule: NSTextCheckingResult?] = [:]

        while location < end {
            var best: (rule: Rule, match: NSTextCheckingResult)?
            for rule in rules {
                var candidate: NSTextCheckingResult?
                if let cached = cache[rule], cached == nil || cached!.range.location >= location {
                    candidate = cached
                } else {
                    candidate = regexes[rule]!.firstMatch(in: string, options: [.withTransparentBounds],
                                                          range: NSRange(location: location, length: end - location))
                    cache[rule] = .some(candidate)
                }
                if let c = candidate, best == nil || c.range.location < best!.match.range.location {
                    best = (rule, c)
                }
            }

            guard let (rule, match) = best else {
                nodes.append(.text(NSRange(location: location, length: end - location)))
                break
            }
            if match.range.location > location {
                nodes.append(.text(NSRange(location: location, length: match.range.location - location)))
            }

            let content = match.range(at: 2)
            let markers = [match.range(at: 1), match.range(at: 3)]
            let style: InlineStyle
            switch rule {
            case .note: style = .note
            case .code: style = .code
            case .link: style = .link(url: ns.substring(with: match.range(at: 4)))
            case .boldItalic: style = .boldItalic
            case .bold: style = .bold
            case .italic: style = .italic
            case .underscore: style = mode == .screenplay ? .underline : .italic
            }

            let children: [InlineNode]
            if rule == .code || rule == .note || depth >= 4 {
                children = [.text(content)]
            } else {
                children = parse(ns, range: content, rules: rules, mode: mode, depth: depth + 1)
            }
            nodes.append(.styled(style, content: content, markers: markers, children: children))
            location = NSMaxRange(match.range)
        }
        return nodes
    }
}
