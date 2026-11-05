import AppKit
import ScriptaCore

/// Live formatter: classifies every line (Fountain or Markdown) and applies typographic
/// attributes to the text storage while the user types, like Highland 2.
///
/// The whole document is re-parsed on each edit (parsing is linear and cheap), but attributes
/// are only re-applied to lines that were edited or whose classification changed — e.g. a line
/// that becomes a character cue turns the following line into dialogue.
@MainActor
final class SyntaxHighlighter: NSObject, NSTextStorageDelegate {
    private(set) var mode: DocumentMode
    private(set) var scale: CGFloat = 1
    private(set) var style: EditorStyle
    weak var textView: NSTextView?

    private struct Signature: Equatable {
        let kind: LineKind
        let length: Int
        let textOffset: Int
        let textLength: Int
        let markers: [NSRange]
    }

    private var signatures: [Int: Signature] = [:]
    private var overlays: [NSRange] = []
    private var needsFullPass = true
    private var isApplying = false

    init(mode: DocumentMode) {
        self.mode = mode
        self.style = EditorStyle(mode: mode)
    }

    func setMode(_ mode: DocumentMode, scale: CGFloat, in storage: NSTextStorage) {
        self.mode = mode
        self.scale = scale
        style = EditorStyle(mode: mode, scale: scale)
        rehighlight(storage)
    }

    /// Restyles the entire document.
    func rehighlight(_ storage: NSTextStorage) {
        needsFullPass = true
        isApplying = true
        storage.beginEditing()
        apply(to: storage, editedRange: NSRange(location: 0, length: storage.length), delta: 0)
        storage.endEditing()
        isApplying = false
    }

    // MARK: - NSTextStorageDelegate

    nonisolated func textStorage(_ textStorage: NSTextStorage,
                                 willProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange,
                                 changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Text storage edits always originate from the text view on the main thread.
        nonisolated(unsafe) let textStorage = textStorage
        MainActor.assumeIsolated {
            guard !isApplying else { return }
            // Never restyle while an input method is composing (dead keys, accents, CJK…).
            if let textView, textView.hasMarkedText() {
                needsFullPass = true
                return
            }
            isApplying = true
            apply(to: textStorage, editedRange: editedRange, delta: delta)
            isApplying = false
        }
    }

    // MARK: - Styling

    private func apply(to storage: NSTextStorage, editedRange: NSRange, delta: Int) {
        let ns = storage.mutableString as NSString
        let length = ns.length
        let lines = mode == .screenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns)

        let newOverlays = overlayRanges(ns)
        let oldEditEnd = NSMaxRange(editedRange) - delta
        let shiftedOld = overlays.map { $0.location >= oldEditEnd ? $0.shifted(by: delta) : $0 }
        let full = needsFullPass || shiftedOld != newOverlays
        needsFullPass = false

        let touched: NSRange = {
            let clamped = NSIntersectionRange(editedRange, NSRange(location: 0, length: length))
            return length == 0 ? NSRange(location: 0, length: 0) : ns.lineRange(for: clamped)
        }()

        if full, length > 0 {
            storage.setAttributes(style.baseAttributes, range: NSRange(location: 0, length: length))
        }

        var newSignatures: [Int: Signature] = [:]
        newSignatures.reserveCapacity(lines.count)
        for line in lines {
            let signature = Signature(kind: line.kind, length: line.range.length,
                                      textOffset: line.textRange.location - line.range.location,
                                      textLength: line.textRange.length,
                                      markers: line.markers.map { $0.shifted(by: -line.range.location) })
            newSignatures[line.range.location] = signature

            var restyle = full
            if !restyle {
                let loc = line.range.location
                if loc >= touched.location, loc <= NSMaxRange(touched) {
                    restyle = true
                } else {
                    let oldLocation = loc >= NSMaxRange(editedRange) ? loc - delta : loc
                    restyle = signatures[oldLocation] != signature
                }
            }
            if restyle { style(line, in: storage, ns: ns, reset: !full) }
        }
        signatures = newSignatures
        overlays = newOverlays

        for range in newOverlays where NSMaxRange(range) <= length {
            let isNote = range.length >= 2 && ns.substring(with: NSRange(location: range.location, length: 2)) == "[["
            storage.addAttribute(.foregroundColor, value: isNote ? EditorStyle.notesColor : EditorStyle.boneyardColor, range: range)
        }

        textView?.typingAttributes = style.baseAttributes
    }

    private func style(_ line: ScriptLine, in storage: NSTextStorage, ns: NSString, reset: Bool) {
        let element = style.element(for: line.kind)
        if reset, line.fullRange.length > 0 {
            storage.setAttributes(style.baseAttributes, range: line.fullRange)
        }
        if line.fullRange.length > 0 {
            storage.addAttribute(.paragraphStyle, value: element.paragraph, range: line.fullRange)
        }
        guard line.range.length > 0 else { return }
        storage.addAttributes([.font: element.font, .foregroundColor: element.color], range: line.range)

        if line.kind.allowsInlineMarkup, line.textRange.length > 0 {
            applyInline(InlineParser.parse(ns, range: line.textRange, mode: mode), font: element.font, storage: storage)
        }
        for marker in line.markers where marker.length > 0 {
            storage.addAttribute(.foregroundColor, value: EditorStyle.markerColor, range: marker)
        }
    }

    private func applyInline(_ nodes: [InlineNode], font: NSFont, storage: NSTextStorage) {
        let fm = NSFontManager.shared
        for node in nodes {
            guard case let .styled(inline, content, markers, children) = node else { continue }
            var nested = font
            switch inline {
            case .bold:
                nested = fm.convert(font, toHaveTrait: .boldFontMask)
            case .italic:
                nested = fm.convert(font, toHaveTrait: .italicFontMask)
            case .boldItalic:
                nested = fm.convert(fm.convert(font, toHaveTrait: .boldFontMask), toHaveTrait: .italicFontMask)
            case .underline:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            case .code:
                nested = .monospacedSystemFont(ofSize: font.pointSize * 0.85, weight: .regular)
            case .link:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            case .note:
                storage.addAttribute(.foregroundColor, value: EditorStyle.notesColor, range: content)
            }
            if nested != font { storage.addAttribute(.font, value: nested, range: content) }
            for marker in markers where marker.length > 0 {
                storage.addAttribute(.foregroundColor, value: inline == .note ? EditorStyle.notesColor : EditorStyle.markerColor,
                                     range: marker)
            }
            if inline != .code, inline != .note {
                applyInline(children, font: nested, storage: storage)
            }
        }
    }

    /// Multi-line constructs styled on top of the line classification (notes and boneyard / comments).
    private func overlayRanges(_ ns: NSString) -> [NSRange] {
        switch mode {
        case .screenplay:
            (TextLines.matches(FountainParser.boneyardRegex, in: ns) + TextLines.matches(FountainParser.noteRegex, in: ns))
                .sorted { $0.location < $1.location }
        case .prose:
            TextLines.matches(MarkdownParser.commentRegex, in: ns)
        }
    }
}
