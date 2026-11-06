import Foundation

/// Converts Fountain or Markdown source into a complete, self-contained HTML document.
public enum HTMLRenderer {
    public struct Result: Sendable {
        public var html: String
        public var title: String
        public var author: String?
        public var hasTitlePage: Bool
    }

    public static func render(text: String, mode: DocumentMode, options: ExportOptions,
                       fallbackTitle: String, forPrint: Bool) -> Result {
        let source = cleanedSource(text, mode: mode, includeNotes: options.includeNotes)
        let ns = source as NSString
        let layout = PageLayout.layout(for: mode, paper: options.paper)

        var body: String
        var title = fallbackTitle
        var author: String?
        var hasTitlePage = false
        switch mode {
        case .screenplay:
            let rendered = renderScreenplay(ns, options: options)
            body = rendered.body
            if let t = rendered.title, !t.isEmpty { title = t }
            author = rendered.author
            hasTitlePage = rendered.hasTitlePage
        case .prose:
            let rendered = renderProse(ns, includeNotes: options.includeNotes)
            body = rendered.body
            if let t = rendered.title, !t.isEmpty { title = t }
        }
        if body.isEmpty { body = "<p></p>" }

        let css = ExportTemplates.stylesheet(for: mode, layout: layout, paper: options.paper, forPrint: forPrint)
        var meta = "<meta name=\"generator\" content=\"Scripta\">\n"
        if let author { meta += "<meta name=\"author\" content=\"\(escapeAttribute(author))\">\n" }
        let html = """
            <!DOCTYPE html>
            <html lang="it">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            \(meta)<title>\(escape(title))</title>
            <style>
            \(css)</style>
            </head>
            <body class="\(mode == .screenplay ? "screenplay" : "prose")">
            \(body)
            </body>
            </html>

            """
        return Result(html: html, title: title, author: author, hasTitlePage: hasTitlePage)
    }

    // MARK: - Source cleanup

    /// Removes boneyard / comments (never printed) and, optionally, notes.
    public static func cleanedSource(_ text: String, mode: DocumentMode, includeNotes: Bool) -> String {
        let regex = mode == .screenplay ? FountainParser.boneyardRegex : MarkdownParser.commentRegex
        var result = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                    withTemplate: "")
        if !includeNotes {
            result = FountainParser.noteRegex.stringByReplacingMatches(
                in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
        }
        return result
    }

    // MARK: - Screenplay

    private static func renderScreenplay(_ ns: NSString, options: ExportOptions)
        -> (body: String, title: String?, author: String?, hasTitlePage: Bool) {
        let lines = FountainParser.parse(ns)
        func inline(_ line: ScriptLine) -> String {
            inlineHTML(ns, range: line.textRange, mode: .screenplay)
        }

        // Title page fields, in order of appearance, with multi-line values.
        var fields: [(key: String, values: [String])] = []
        var plainTitle: String?
        var plainAuthor: String?
        var blocks: [String] = []
        var lastWasDialogue = false
        var index = 0

        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .titleField(let key):
                let value = inline(line)
                if line.markers.isEmpty, let last = fields.indices.last, fields[last].key == key {
                    if !value.isEmpty { fields[last].values.append(value) }
                } else {
                    fields.append((key, value.isEmpty ? [] : [value]))
                }
                let plain = plainText(ns, line.textRange, mode: .screenplay)
                if key == "title", !plain.isEmpty { plainTitle = [plainTitle, plain].compactMap { $0 }.joined(separator: " ") }
                if key == "author" || key == "authors", plainAuthor == nil, !plain.isEmpty { plainAuthor = plain }
                index += 1
                continue

            case .sceneHeading(let number):
                var html = inline(line)
                if options.includeSceneNumbers, let number {
                    let n = escape(number)
                    html = "<span class=\"scene-number left\">\(n)</span>\(html)<span class=\"scene-number right\">\(n)</span>"
                }
                blocks.append("<h3 class=\"scene-heading\">\(html)</h3>")

            case .graphicNovelPage:
                blocks.append("<h3 class=\"graphic-novel-tav\">\(inline(line))</h3>")
            case .panel:
                blocks.append("<h4 class=\"graphic-novel-panel\">\(inline(line))</h4>")
            case .balloon:
                blocks.append("<p class=\"balloon\">\(inline(line))</p>")

            case .action:
                var parts: [String] = []
                while index < lines.count, lines[index].kind == .action {
                    parts.append(inline(lines[index]))
                    index += 1
                }
                blocks.append("<p class=\"action\">\(parts.joined(separator: "\n"))</p>")
                lastWasDialogue = false
                continue

            case .character(let dual):
                var html = "<div class=\"dialogue-block\">\n<p class=\"character\">\(inline(line))</p>\n"
                index += 1
                var speech: [String] = []
                func flushSpeech() {
                    if !speech.isEmpty { html += "<p class=\"dialogue\">\(speech.joined(separator: "<br>"))</p>\n" }
                    speech.removeAll()
                }
                while index < lines.count {
                    let next = lines[index]
                    if next.kind == .parenthetical {
                        flushSpeech()
                        html += "<p class=\"parenthetical\">\(inline(next))</p>\n"
                    } else if next.kind == .dialogue {
                        speech.append(inline(next))
                    } else if next.kind == .note, options.includeNotes {
                        flushSpeech()
                        html += "<p class=\"dialogue note\">\(inline(next))</p>\n"
                    } else {
                        break
                    }
                    index += 1
                }
                flushSpeech()
                html += "</div>"

                if dual, lastWasDialogue, let previous = blocks.popLast() {
                    blocks.append("<div class=\"dual\">\n\(previous)\n\(html)\n</div>")
                    lastWasDialogue = false
                } else {
                    blocks.append(html)
                    lastWasDialogue = true
                }
                continue

            case .parenthetical:
                blocks.append("<p class=\"parenthetical\">\(inline(line))</p>")
            case .dialogue:
                blocks.append("<p class=\"dialogue\">\(inline(line))</p>")
            case .transition:
                blocks.append("<p class=\"transition\">\(inline(line))</p>")
            case .centered:
                blocks.append("<p class=\"centered\">\(inline(line))</p>")
            case .lyrics:
                blocks.append("<p class=\"lyrics\">\(inline(line))</p>")
            case .pageBreak:
                blocks.append("<div class=\"page-break\"></div>")
            case .note:
                if options.includeNotes { blocks.append("<p class=\"note\">\(inline(line))</p>") }
            case .empty, .section, .synopsis, .boneyard:
                // Structural elements are not printed (Fountain spec).
                index += 1
                continue
            default:
                blocks.append("<p class=\"action\">\(inline(line))</p>")
            }
            lastWasDialogue = false
            index += 1
        }

        var titlePage = ""
        if options.includeTitlePage, !fields.isEmpty {
            func values(_ keys: String...) -> [String] {
                fields.filter { keys.contains($0.key) }.flatMap(\.values)
            }
            let titleLines = values("title")
            var block = "<div class=\"title-block\">\n"
            if !titleLines.isEmpty { block += "<h1 class=\"title\">\(titleLines.joined(separator: "<br>"))</h1>\n" }
            if !values("episode").isEmpty { block += "<p class=\"author\">\(values("episode").joined(separator: "<br>"))</p>\n" }
            if !values("credit").isEmpty { block += "<p class=\"credit\">\(values("credit").joined(separator: "<br>"))</p>\n" }
            if !values("author", "authors").isEmpty { block += "<p class=\"author\">\(values("author", "authors").joined(separator: "<br>"))</p>\n" }
            if !values("source").isEmpty { block += "<p class=\"source\">\(values("source").joined(separator: "<br>"))</p>\n" }
            block += "</div>\n"
            let contact = values("contact").joined(separator: "\n")
            let meta = values("draft date", "date", "revision", "copyright", "notes").joined(separator: "\n")
            block += "<div class=\"footer\"><div class=\"contact\">\(contact)</div><div class=\"meta\">\(meta)</div></div>\n"
            titlePage = "<section class=\"title-page\">\n\(block)</section>\n"
        }

        let hasTitlePage = !titlePage.isEmpty
        return (titlePage + blocks.joined(separator: "\n"), plainTitle, plainAuthor, hasTitlePage)
    }

    // MARK: - Prose

    private enum ProseBlock {
        case heading(Int, ScriptLine)
        case graphicNovelPage(ScriptLine)
        case panel(ScriptLine)
        case balloon(ScriptLine)
        case paragraph([ScriptLine])
        case quote([ScriptLine])
        case list([ScriptLine])
        case code([ScriptLine])
        case rule
        case pageBreak
    }

    private static func renderProse(_ ns: NSString, includeNotes: Bool) -> (body: String, title: String?) {
        let lines = MarkdownParser.parse(ns)
        var blocks: [ProseBlock] = []
        var index = 0
        var title: String?

        func isListItem(_ kind: LineKind) -> Bool {
            if case .bullet = kind { return true }
            if case .ordered = kind { return true }
            return false
        }

        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .heading(let level):
                if level == 1, title == nil { title = plainText(ns, line.textRange, mode: .prose) }
                blocks.append(.heading(level, line))
                index += 1
            case .graphicNovelPage:
                blocks.append(.graphicNovelPage(line))
                index += 1
            case .panel:
                blocks.append(.panel(line))
                index += 1
            case .balloon:
                blocks.append(.balloon(line))
                index += 1
            case .paragraph:
                var group: [ScriptLine] = []
                while index < lines.count, lines[index].kind == .paragraph {
                    group.append(lines[index]); index += 1
                }
                blocks.append(.paragraph(group))
            case .blockquote:
                var group: [ScriptLine] = []
                while index < lines.count, lines[index].kind == .blockquote || (lines[index].kind == .paragraph && !group.isEmpty) {
                    group.append(lines[index]); index += 1
                }
                blocks.append(.quote(group))
            case .bullet, .ordered:
                var group: [ScriptLine] = []
                while index < lines.count {
                    let kind = lines[index].kind
                    if isListItem(kind) || (kind == .paragraph && !group.isEmpty) {
                        group.append(lines[index]); index += 1
                    } else if kind == .empty, index + 1 < lines.count, isListItem(lines[index + 1].kind) {
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(group))
            case .codeFence:
                index += 1
                var group: [ScriptLine] = []
                while index < lines.count, lines[index].kind == .code {
                    group.append(lines[index]); index += 1
                }
                if index < lines.count, lines[index].kind == .codeFence { index += 1 }
                blocks.append(.code(group))
            case .code:
                index += 1
            case .rule:
                blocks.append(.rule); index += 1
            case .pageBreak:
                blocks.append(.pageBreak); index += 1
            default:
                index += 1
            }
        }

        func joinInline(_ group: [ScriptLine]) -> String {
            var out = ""
            for (i, line) in group.enumerated() {
                out += inlineHTML(ns, range: line.textRange, mode: .prose)
                guard i < group.count - 1 else { break }
                let hardBreak = line.range.length >= 2 && ns.substring(with: NSRange(location: NSMaxRange(line.range) - 2, length: 2)) == "  "
                out += hardBreak ? "<br>\n" : "\n"
            }
            return out
        }

        var html: [String] = []
        for block in blocks {
            switch block {
            case .heading(let level, let line):
                html.append("<h\(level)>\(inlineHTML(ns, range: line.textRange, mode: .prose))</h\(level)>")
            case .graphicNovelPage(let line):
                html.append("<h3 class=\"graphic-novel-tav\">\(inlineHTML(ns, range: line.textRange, mode: .prose))</h3>")
            case .panel(let line):
                html.append("<h4 class=\"graphic-novel-panel\">\(inlineHTML(ns, range: line.textRange, mode: .prose))</h4>")
            case .balloon(let line):
                html.append("<p class=\"balloon\">\(inlineHTML(ns, range: line.textRange, mode: .prose))</p>")
            case .paragraph(let group):
                html.append("<p>\(joinInline(group))</p>")
            case .quote(let group):
                // Empty quote lines (">") split the quotation into paragraphs.
                var paragraphs: [[ScriptLine]] = [[]]
                for line in group {
                    if line.textRange.length == 0 { paragraphs.append([]) } else { paragraphs[paragraphs.count - 1].append(line) }
                }
                let inner = paragraphs.filter { !$0.isEmpty }.map { "<p>\(joinInline($0))</p>" }.joined(separator: "\n")
                html.append("<blockquote>\n\(inner)\n</blockquote>")
            case .list(let group):
                html.append(renderList(group, ns: ns))
            case .code(let group):
                let code = group.map { escape(ns.substring(with: $0.range)) }.joined(separator: "\n")
                html.append("<pre><code>\(code)</code></pre>")
            case .rule:
                html.append("<hr>")
            case .pageBreak:
                html.append("<div class=\"page-break\"></div>")
            }
        }
        return (html.joined(separator: "\n"), title)
    }

    private static func renderList(_ lines: [ScriptLine], ns: NSString) -> String {
        var out = ""
        var stack: [(indent: Int, tag: String)] = []
        for line in lines {
            let indent: Int, tag: String, number: Int
            switch line.kind {
            case .bullet(let i): (indent, tag, number) = (i, "ul", 1)
            case .ordered(let i, let n): (indent, tag, number) = (i, "ol", n)
            default:
                // Lazy continuation of the previous item.
                out += "\n" + inlineHTML(ns, range: line.textRange, mode: .prose)
                continue
            }
            while let last = stack.last, indent < last.indent {
                out += "</li></\(last.tag)>"
                stack.removeLast()
            }
            if let last = stack.last, indent == last.indent {
                if last.tag == tag {
                    out += "</li>"
                } else {
                    out += "</li></\(last.tag)>"
                    stack.removeLast()
                }
            }
            if stack.last.map({ indent > $0.indent }) ?? true {
                let start = tag == "ol" && number != 1 ? " start=\"\(number)\"" : ""
                out += "<\(tag)\(start)>"
                stack.append((indent, tag))
            }
            out += "<li>" + inlineHTML(ns, range: line.textRange, mode: .prose)
        }
        while let last = stack.popLast() {
            out += "</li></\(last.tag)>"
        }
        return out
    }

    // MARK: - Inline

    public static func inlineHTML(_ ns: NSString, range: NSRange, mode: DocumentMode) -> String {
        render(InlineParser.parse(ns, range: range, mode: mode), ns)
    }

    private static func render(_ nodes: [InlineNode], _ ns: NSString) -> String {
        var out = ""
        for node in nodes {
            switch node {
            case .text(let range):
                out += escape(ns.substring(with: range))
            case let .styled(style, content, _, children):
                let inner = render(children, ns)
                switch style {
                case .bold: out += "<strong>\(inner)</strong>"
                case .italic: out += "<em>\(inner)</em>"
                case .boldItalic: out += "<strong><em>\(inner)</em></strong>"
                case .underline: out += "<u>\(inner)</u>"
                case .code: out += "<code>\(escape(ns.substring(with: content)))</code>"
                case .note: out += "<span class=\"note\">[\(inner)]</span>"
                case .link(let url): out += "<a href=\"\(escapeAttribute(url))\">\(inner)</a>"
                }
            }
        }
        return out
    }

    /// Inline text with markup removed (for titles and metadata).
    public static func plainText(_ ns: NSString, _ range: NSRange, mode: DocumentMode) -> String {
        func flatten(_ nodes: [InlineNode]) -> String {
            nodes.map { node in
                switch node {
                case .text(let r): ns.substring(with: r)
                case let .styled(_, _, _, children): flatten(children)
                }
            }.joined()
        }
        return flatten(InlineParser.parse(ns, range: range, mode: mode)).trimmingCharacters(in: .whitespaces)
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }

    public static func escapeAttribute(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
