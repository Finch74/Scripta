import CGtk
import Foundation
import ScriptaCore

/// Maps the UTF-16 offsets used by ScriptaCore (NSString ranges) to the character
/// (Unicode scalar) offsets used by GtkTextBuffer.
struct OffsetMap {
    private var table: [Int32] = []

    init(_ text: String) {
        table.reserveCapacity(text.utf16.count + 1)
        var scalar: Int32 = 0
        for character in text.unicodeScalars {
            table.append(scalar)
            if character.utf16.count == 2 { table.append(scalar) }
            scalar += 1
        }
        table.append(scalar)
    }

    func characterOffset(_ utf16Offset: Int) -> Int32 {
        table[min(max(utf16Offset, 0), table.count - 1)]
    }
}

/// Styles a GtkTextBuffer with text tags, from the same line classification as the macOS editor.
/// Tag names mirror the line kinds; the screenplay indents follow the usual layout (character cue,
/// parenthetical and dialogue progressively indented, transitions on the right).
@MainActor
final class Highlighter {
    /// Left margin of the text view; tags that set `left-margin` replace it, so they include it.
    static let baseMargin: Int32 = 48

    private enum Value {
        case string(String), int(Int32), double(Double)
    }

    private let buffer: Object
    private var tags: [String: Object] = [:]
    private var map = OffsetMap("")

    init(buffer: Object) {
        self.buffer = buffer
        let bold = Value.int(Int32(PANGO_WEIGHT_BOLD.rawValue))
        let italic = Value.int(Int32(PANGO_STYLE_ITALIC.rawValue))
        let dim = Value.string("#8a8a8a")
        let accent = Value.string("#3584e4")
        let margin = Self.baseMargin

        // Later tags take priority over earlier ones: markers and comments come last.
        define("scene", ["weight": bold, "foreground": accent, "pixels-above-lines": .int(12)])
        define("character", ["weight": bold, "left-margin": .int(margin + 200)])
        define("parenthetical", ["left-margin": .int(margin + 150), "style": italic])
        define("dialogue", ["left-margin": .int(margin + 100), "right-margin": .int(100)])
        define("transition", ["weight": bold, "justification": .int(Int32(GTK_JUSTIFY_RIGHT.rawValue))])
        define("centered", ["justification": .int(Int32(GTK_JUSTIFY_CENTER.rawValue))])
        define("lyrics", ["style": italic])
        define("section", ["weight": bold, "foreground": .string("#9141ac"), "scale": .double(1.15)])
        define("synopsis", ["style": italic, "foreground": dim])
        define("title-field", ["foreground": dim])
        for (level, scale) in [1.8, 1.5, 1.25, 1.1].enumerated() {
            define("h\(level + 1)", ["weight": bold, "scale": .double(scale), "pixels-above-lines": .int(8)])
        }
        define("quote", ["style": italic, "foreground": dim, "left-margin": .int(margin + 24)])
        define("code", ["family": .string("monospace"), "paragraph-background": .string("rgba(127,127,127,0.12)")])
        define("page", ["weight": bold, "foreground": .string("#c64600"), "scale": .double(1.3), "pixels-above-lines": .int(12)])
        define("panel", ["weight": bold, "foreground": .string("#2190a4")])
        define("balloon-name", ["foreground": accent])
        define("bold", ["weight": bold])
        define("italic", ["style": italic])
        define("underline", ["underline": .int(Int32(PANGO_UNDERLINE_SINGLE.rawValue))])
        define("inline-code", ["family": .string("monospace")])
        define("link", ["foreground": accent, "underline": .int(Int32(PANGO_UNDERLINE_SINGLE.rawValue))])
        define("dim", ["foreground": dim])
        define("comment", ["foreground": dim, "style": italic])
        define("marker", ["foreground": dim, "weight": .int(Int32(PANGO_WEIGHT_NORMAL.rawValue))])
    }

    private func define(_ name: String, _ properties: [String: Value]) {
        let tag = raw(gtk_text_tag_new(name))!
        for (property, value) in properties {
            switch value {
            case .string(let string): scripta_object_set_string(tag, property, string)
            case .int(let int): scripta_object_set_int(tag, property, int)
            case .double(let double): scripta_object_set_double(tag, property, double)
            }
        }
        gtk_text_tag_table_add(gtk_text_buffer_get_tag_table(cast(buffer)), cast(tag))
        g_object_unref(tag)
        tags[name] = tag
    }

    /// Re-styles the whole buffer. Returns the offset map of `text`, valid until the next edit.
    @discardableResult
    func apply(text: String, mode: DocumentMode) -> OffsetMap {
        map = OffsetMap(text)
        var start = GtkTextIter(), end = GtkTextIter()
        gtk_text_buffer_get_bounds(cast(buffer), &start, &end)
        gtk_text_buffer_remove_all_tags(cast(buffer), &start, &end)

        let ns = text as NSString
        let lines = mode == .screenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns)
        for line in lines {
            if let name = tagName(for: line.kind) { tag(name, line.range) }
            if line.kind == .balloon, let parts = GraphicNovel.balloonParts(ns, line.range) {
                tag("balloon-name", parts.name)
            }
            if line.kind.allowsInlineMarkup {
                applyInline(InlineParser.parse(ns, range: line.textRange, mode: mode))
            }
            for marker in line.markers { tag("marker", marker) }
        }
        return map
    }

    private func tagName(for kind: LineKind) -> String? {
        switch kind {
        case .sceneHeading: "scene"
        case .character: "character"
        case .parenthetical: "parenthetical"
        case .dialogue: "dialogue"
        case .transition: "transition"
        case .centered: "centered"
        case .lyrics: "lyrics"
        case .section: "section"
        case .synopsis: "synopsis"
        case .titleField: "title-field"
        case .boneyard, .note: "comment"
        case .pageBreak, .rule, .codeFence: "dim"
        case .heading(let level): "h\(min(max(level, 1), 4))"
        case .blockquote: "quote"
        case .code: "code"
        case .graphicNovelPage: "page"
        case .panel: "panel"
        default: nil
        }
    }

    private func applyInline(_ nodes: [InlineNode]) {
        for node in nodes {
            guard case let .styled(style, content, markers, children) = node else { continue }
            switch style {
            case .bold: tag("bold", content)
            case .italic: tag("italic", content)
            case .boldItalic: tag("bold", content); tag("italic", content)
            case .underline: tag("underline", content)
            case .code: tag("inline-code", content)
            case .note: tag("comment", content)
            case .link: tag("link", content)
            }
            applyInline(children)
            for marker in markers { tag("marker", marker) }
        }
    }

    private func tag(_ name: String, _ range: NSRange) {
        guard range.length > 0, let tag = tags[name] else { return }
        var start = GtkTextIter(), end = GtkTextIter()
        gtk_text_buffer_get_iter_at_offset(cast(buffer), &start, map.characterOffset(range.location))
        gtk_text_buffer_get_iter_at_offset(cast(buffer), &end, map.characterOffset(NSMaxRange(range)))
        gtk_text_buffer_apply_tag(cast(buffer), cast(tag), &start, &end)
    }
}
