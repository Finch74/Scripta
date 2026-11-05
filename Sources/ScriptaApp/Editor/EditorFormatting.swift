import AppKit
import SwiftUI
import ScriptaCore

/// Format menu actions. They are sent through the responder chain (`NSApp.sendAction(_:to: nil, …)`),
/// so they reach whichever editor is first responder; each one is a single undoable edit that
/// inserts plain-text markup (Fountain and Markdown share `**`, `*`, `#` and `===`).
extension EditorTextView {
    @objc func formatBold(_ sender: Any?) { toggleEmphasis("*", count: 2, actionName: "Grassetto") }
    @objc func formatItalic(_ sender: Any?) { toggleEmphasis("*", count: 1, actionName: "Corsivo") }
    /// Fountain only: `_text_` is underline in Fountain but italic in Markdown.
    @objc func formatUnderline(_ sender: Any?) { toggleEmphasis("_", count: 1, actionName: "Sottolineato") }

    @objc func formatHeading1(_ sender: Any?) { setHeading(level: 1) }
    @objc func formatHeading2(_ sender: Any?) { setHeading(level: 2) }
    @objc func formatHeading3(_ sender: Any?) { setHeading(level: 3) }
    @objc func formatBodyText(_ sender: Any?) { setHeading(level: 0) }

    /// Inserts `===` on a line of its own, surrounded by blank lines (page break in both formats).
    @objc func formatInsertPageBreak(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let before = ns.substring(to: selection.location)
        let after = ns.substring(from: NSMaxRange(selection))

        var prefix = ""
        if !before.isEmpty {
            prefix = before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        }
        let suffix = after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"
        let insertion = prefix + "===" + suffix
        let caret = selection.location + (insertion as NSString).length
        replace(selection, with: insertion, select: NSRange(location: caret, length: 0), actionName: "Interruzione di pagina")
    }

    // MARK: - Emphasis

    /// Wraps the selection in `count` copies of `marker`, or removes them when the selection
    /// (or the text around it) is already emphasised that way.
    private func toggleEmphasis(_ marker: Character, count: Int, actionName: String) {
        let ns = string as NSString
        var selection = selectedRange()
        let unit = String(marker).utf16.first!

        // Double-click selects a trailing space too: keep it outside the markers.
        while selection.length > 0, ns.character(at: NSMaxRange(selection) - 1) == 0x20 { selection.length -= 1 }

        func run(from index: Int, step: Int) -> Int {
            var n = 0, i = index
            while i >= 0, i < ns.length, ns.character(at: i) == unit { n += 1; i += step }
            return n
        }
        // A run of asterisks means: 1 = italic, 2 = bold, 3 = bold italic.
        func matches(_ length: Int) -> Bool {
            marker == "*" ? (count == 2 ? length >= 2 : length == 1 || length == 3) : length >= count
        }

        // Markers just outside the selection: "**|word|**".
        let outside = min(run(from: selection.location - 1, step: -1), run(from: NSMaxRange(selection), step: 1))
        if selection.length > 0, matches(outside) {
            let inner = ns.substring(with: selection)
            let range = NSRange(location: selection.location - count, length: selection.length + 2 * count)
            replace(range, with: inner, select: NSRange(location: range.location, length: selection.length), actionName: actionName)
            return
        }

        // Markers inside the selection: "|**word**|".
        let inside = min(run(from: selection.location, step: 1), run(from: NSMaxRange(selection) - 1, step: -1))
        if selection.length > 2 * count, matches(inside), inside * 2 < selection.length {
            let inner = ns.substring(with: NSRange(location: selection.location + count, length: selection.length - 2 * count))
            replace(selection, with: inner, select: NSRange(location: selection.location, length: (inner as NSString).length),
                    actionName: actionName)
            return
        }

        let markers = String(repeating: marker, count: count)
        let inner = ns.substring(with: selection)
        replace(selection, with: markers + inner + markers,
                select: NSRange(location: selection.location + count, length: selection.length), actionName: actionName)
    }

    // MARK: - Headings

    /// Sets the `#` level of every line touched by the selection (0 removes it). In Fountain
    /// the same syntax produces sections.
    private func setHeading(level: Int) {
        let ns = string as NSString
        let selection = selectedRange()
        let lines = ns.lineRange(for: selection)
        let original = ns.substring(with: lines)

        let rewritten = original.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return line } // blank lines stay blank
            let body = trimmed.drop { $0 == "#" }.drop { $0 == " " || $0 == "\t" }
            return level > 0 ? String(repeating: "#", count: level) + " " + body : String(body)
        }
        let replacement = rewritten.joined(separator: "\n")
        guard replacement != original else { return }

        // A caret keeps its offset from the end of its line; a selection covers the rewritten lines.
        let newLength = (replacement as NSString).length
        let lineEnd = lines.location + newLength - (replacement.hasSuffix("\n") ? 1 : 0)
        let newSelection = selection.length == 0
            ? NSRange(location: max(lines.location, min(selection.location + newLength - lines.length, lineEnd)), length: 0)
            : NSRange(location: lines.location, length: newLength)
        replace(lines, with: replacement, select: newSelection,
                actionName: level == 0 ? "Testo normale" : "Titolo \(level)")
    }

    // MARK: - Editing primitive

    /// Replaces text as a single undoable user edit (also notifies the delegate, so the document updates).
    private func replace(_ range: NSRange, with text: String, select selection: NSRange, actionName: String) {
        guard let textStorage, shouldChangeText(in: range, replacementString: text) else { return }
        textStorage.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
        undoManager?.setActionName(actionName)
    }
}

// MARK: - Menu

struct DocumentModeKey: FocusedValueKey {
    typealias Value = DocumentMode
}

extension FocusedValues {
    /// Mode of the focused document (used to enable Fountain-only commands).
    var documentMode: DocumentMode? {
        get { self[DocumentModeKey.self] }
        set { self[DocumentModeKey.self] = newValue }
    }
}

/// "Formato" menu.
struct FormatCommands: Commands {
    @FocusedValue(\.documentMode) private var mode
    @FocusedValue(\.viewMode) private var viewMode

    /// Formatting only makes sense while the editor (not the preview) is showing.
    private var isEditing: Bool { mode != nil && viewMode?.wrappedValue != .preview }

    var body: some Commands {
        CommandMenu("Formato") {
            Group {
                Button("Grassetto") { send(#selector(EditorTextView.formatBold(_:))) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Corsivo") { send(#selector(EditorTextView.formatItalic(_:))) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Sottolineato") { send(#selector(EditorTextView.formatUnderline(_:))) }
                    .keyboardShortcut("u", modifiers: .command)
                    .disabled(mode != .screenplay)
                Divider()
                Button(mode == .screenplay ? "Sezione 1" : "Titolo 1") { send(#selector(EditorTextView.formatHeading1(_:))) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(mode == .screenplay ? "Sezione 2" : "Titolo 2") { send(#selector(EditorTextView.formatHeading2(_:))) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button(mode == .screenplay ? "Sezione 3" : "Titolo 3") { send(#selector(EditorTextView.formatHeading3(_:))) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Testo normale") { send(#selector(EditorTextView.formatBodyText(_:))) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                Button("Interruzione di pagina") { send(#selector(EditorTextView.formatInsertPageBreak(_:))) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .disabled(!isEditing)
        }
    }

    @MainActor
    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
