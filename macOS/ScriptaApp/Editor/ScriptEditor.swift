import AppKit
import SwiftUI
import ScriptaCore

/// NSTextView that keeps a fixed-width writing column centred in the window.
final class EditorTextView: NSTextView {
    var columnWidth: CGFloat = 600 {
        didSet { updateInsets() }
    }

    /// Keeps the caret line at the vertical centre of the editor while typing.
    var typewriterScrolling = false {
        didSet {
            guard typewriterScrolling != oldValue else { return }
            updateInsets()
            if typewriterScrolling { centerCaretLine() }
        }
    }

    /// Dims everything except the line or paragraph holding the caret.
    var focusMode = false {
        didSet { if focusMode != oldValue { updateFocus() } }
    }

    var focusScope: FocusScope = .paragraph {
        didSet { if focusScope != oldValue { updateFocus() } }
    }

    /// Background tint of each highlighted character's speeches, keyed by normalised name.
    var characterHighlights: [String: NSColor] = [:] {
        didSet { if characterHighlights != oldValue { updateCharacterHighlights() } }
    }

    /// Parser used to find speeches (screenplay cues or graphic-novel balloons).
    var documentMode: DocumentMode = .screenplay {
        didSet { if documentMode != oldValue { updateCharacterHighlights() } }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        let horizontal = max(32, floor((bounds.width - columnWidth) / 2))
        // Typewriter mode needs half a screen of padding so the first and last lines can reach the centre.
        let visibleHeight = enclosingScrollView?.contentView.bounds.height ?? 0
        let vertical = typewriterScrolling ? max(72, floor(visibleHeight / 2)) : 72
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset {
            textContainerInset = inset
            if let textContainer { layoutManager?.textContainerChangedGeometry(textContainer) }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        guard let clipView = superview as? NSClipView else { return }
        clipView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewFrameDidChange(_:)),
                                               name: NSView.frameDidChangeNotification, object: clipView)
    }

    @objc private func clipViewFrameDidChange(_ notification: Notification) {
        updateInsets()
        if typewriterScrolling { centerCaretLine() }
    }

    // MARK: - Typewriter scrolling

    /// NSTextView calls this after typing and caret movement: in typewriter mode the caret line
    /// is centred instead of merely being kept visible.
    override func scrollRangeToVisible(_ range: NSRange) {
        guard typewriterScrolling, selectedRange().length == 0 else {
            super.scrollRangeToVisible(range)
            return
        }
        centerCaretLine()
    }

    func centerCaretLine() {
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView else { return }
        let length = (string as NSString).length
        let location = min(selectedRange().location, length)

        // Non-contiguous layout: lay out everything up to the caret before measuring.
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: location))
        let lineRect: NSRect
        if location == length, layoutManager.extraLineFragmentTextContainer === textContainer {
            lineRect = layoutManager.extraLineFragmentRect
        } else if length > 0 {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            return
        }
        ensureLayout(below: lineRect)

        let clipView = scrollView.contentView
        let maxY = max(0, frame.height - clipView.bounds.height)
        let targetY = min(maxY, max(0, floor(lineRect.midY + textContainerOrigin.y - clipView.bounds.height / 2)))
        guard abs(clipView.bounds.origin.y - targetY) >= 1 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Lays out one viewport of text below `lineRect`. With non-contiguous layout the view is only
    /// as tall as the text laid out so far: without this, scrolling to a line near the start of a
    /// freshly opened document is clamped by a too-short frame and the editor does not move.
    func ensureLayout(below lineRect: NSRect) {
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView else { return }
        let viewport = NSRect(x: 0, y: lineRect.minY, width: textContainer.size.width,
                              height: scrollView.contentView.bounds.height + lineRect.height)
        layoutManager.ensureLayout(forBoundingRect: viewport, in: textContainer)
    }

    // MARK: - Focus mode

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if focusMode { updateFocus() }
    }

    override func didChangeText() {
        super.didChangeText()
        if focusMode { updateFocus() }
        if !characterHighlights.isEmpty { updateCharacterHighlights() }
    }

    /// Dims inactive text through layout-manager temporary attributes, which affect drawing only:
    /// the text storage (and therefore highlighting, undo and the document) is untouched.
    func updateFocus() {
        guard let layoutManager else { return }
        let ns = string as NSString
        let all = NSRange(location: 0, length: ns.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        guard focusMode, ns.length > 0 else { return }

        let active = focusRange(in: ns, around: selectedRange())
        let before = NSRange(location: 0, length: active.location)
        let after = NSRange(location: NSMaxRange(active), length: ns.length - NSMaxRange(active))
        for range in [before, after] where range.length > 0 {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: EditorStyle.focusDimColor, forCharacterRange: range)
        }
    }

    // MARK: - Character highlighting

    /// Tints the cue and dialogue of highlighted characters. Like focus mode it uses temporary
    /// attributes (a different key, so the two combine) and leaves the text storage untouched.
    func updateCharacterHighlights() {
        guard let layoutManager else { return }
        let ns = string as NSString
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ns.length))
        guard !characterHighlights.isEmpty else { return }
        for speech in CharacterAnalysis.speeches(in: ns, mode: documentMode) {
            guard let color = characterHighlights[speech.name] else { continue }
            let tint = color.withAlphaComponent(0.3)
            for range in speech.textRanges where range.length > 0 {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: tint, forCharacterRange: range)
            }
        }
    }

    private func focusRange(in ns: NSString, around selection: NSRange) -> NSRange {
        // Clamped by hand: NSIntersectionRange turns a caret at the very end into {0, 0}.
        let location = min(selection.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: location, length: min(selection.length, ns.length - location)))
        guard focusScope == .paragraph else { return lineRange }

        // A paragraph is a run of non-blank lines (a dialogue block in Fountain, a paragraph in Markdown).
        func isBlank(_ range: NSRange) -> Bool {
            ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if isBlank(lineRange) { return lineRange }
        var start = lineRange.location
        while start > 0 {
            let previous = ns.lineRange(for: NSRange(location: start - 1, length: 0))
            if isBlank(previous) { break }
            start = previous.location
        }
        var end = NSMaxRange(lineRange)
        while end < ns.length {
            let next = ns.lineRange(for: NSRange(location: end, length: 0))
            if isBlank(next) { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: end - start)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyThemeColors()
    }

    /// Re-assigns the editor colours (all dynamic) so background, caret and selection
    /// are redrawn immediately for the current appearance.
    func applyThemeColors() {
        // textColor is left alone: setting it would recolour the whole storage. The highlighter's
        // per-run colours are dynamic and resolve on redraw.
        backgroundColor = EditorStyle.backgroundColor
        insertionPointColor = EditorStyle.insertionPointColor
        selectedTextAttributes = EditorStyle.selectedTextAttributes
        if let scrollView = enclosingScrollView {
            scrollView.backgroundColor = EditorStyle.backgroundColor
            scrollView.contentView.needsDisplay = true
        }
        needsDisplay = true
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    /// Zoom (⌘+ / ⌘= / ⌘-) and the standard editing shortcuts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘= is the unshifted "+" on US layouts; the View menu only carries ⌘+.
        if flags.subtracting(.shift) == .command, let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "+", "=": EditorZoom.zoomIn(); return true
            case "-": EditorZoom.zoomOut(); return true
            default: break
            }
        }

        guard event.type == .keyDown, window?.firstResponder === self,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        
        switch (key, flags) {
        case ("x", .command): cut(nil)
        case ("c", .command): copy(nil)
        case ("v", .command), ("v", [.command, .shift]), ("v", [.command, .shift, .option]): paste(nil)
        case ("a", .command): selectAll(nil)
        case ("z", .command): undoManager?.undo()
        case ("z", [.command, .shift]): undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

/// Lets SwiftUI views (e.g. the outline sidebar) drive the caret of the AppKit editor,
/// and publishes the caret position back so the outline can follow it.
@MainActor
final class EditorNavigator: ObservableObject {
    fileprivate weak var textView: EditorTextView?

    /// UTF-16 location of the caret (start of the selection) in the editor.
    @Published private(set) var caretLocation = 0

    /// Called by the editor on every selection change. Deferred because selection changes
    /// also happen inside SwiftUI view updates (`updateNSView`), where publishing is not allowed.
    fileprivate func caretDidMove(to location: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.caretLocation != location else { return }
            self.caretLocation = location
        }
    }

    /// Gives keyboard focus back to the editor (e.g. when leaving the preview).
    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Moves the caret to `location` and scrolls so that its line sits near the top of the editor.
    func reveal(location: Int) {
        guard let textView, let layoutManager = textView.layoutManager,
              let scrollView = textView.enclosingScrollView else { return }
        let length = (textView.string as NSString).length
        // TEMP DEBUG: remove once outline navigation is confirmed in the app.
        print("[Outline Click] Target UTF16 Location: \(location), Total Storage Length: \(textView.textStorage?.length ?? 0)")
        let location = min(max(0, location), length)
        let caret = NSRange(location: location, length: 0)

        // Non-contiguous layout: make sure everything up to the target is laid out before measuring.
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: location))
        let lineRect: NSRect
        if location == length, layoutManager.extraLineFragmentTextContainer != nil {
            lineRect = layoutManager.extraLineFragmentRect
        } else if length > 0 {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            lineRect = .zero
        }
        textView.ensureLayout(below: lineRect)
        let clipView = scrollView.contentView
        let maxY = max(0, textView.frame.height - clipView.bounds.height)
        let targetY = min(maxY, max(0, lineRect.minY + textView.textContainerOrigin.y - 24))

        // A click on a row can arrive twice (selection change + tap): nothing to do if already there.
        if textView.selectedRange() == caret, textView.window?.firstResponder === textView,
           textView.typewriterScrolling || abs(clipView.bounds.origin.y - targetY) < 1 {
            return
        }

        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(caret)

        if textView.typewriterScrolling {
            // Keep the typewriter invariant: the caret line sits at the vertical centre.
            textView.centerCaretLine()
        } else {
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }

        let lineRange = (textView.string as NSString).lineRange(for: caret)
        if lineRange.length > 0 { textView.showFindIndicator(for: lineRange) }
    }
}

/// SwiftUI wrapper around the live-formatting editor.
struct ScriptEditor: NSViewRepresentable {
    @Binding var text: String
    var mode: DocumentMode
    var theme: AppTheme
    var behavior: EditorBehavior
    var characterHighlights: [String: NSColor]
    var zoom: CGFloat
    var navigator: EditorNavigator?

    init(text: Binding<String>, mode: DocumentMode, theme: AppTheme = .system,
         behavior: EditorBehavior = EditorBehavior(), characterHighlights: [String: NSColor] = [:],
         zoom: CGFloat = 1, navigator: EditorNavigator? = nil) {
        self._text = text
        self.mode = mode
        self.zoom = zoom
        self.theme = theme
        self.behavior = behavior
        self.characterHighlights = characterHighlights
        self.navigator = navigator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = Self.makeTextSystem()
        scrollView.appearance = theme.appearance
        let storage = textView.textStorage!

        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.highlighter.textView = textView
        navigator?.textView = textView
        storage.delegate = coordinator.highlighter
        textView.delegate = coordinator

        textView.columnWidth = coordinator.highlighter.style.columnWidth
        textView.typingAttributes = coordinator.highlighter.style.baseAttributes
        coordinator.isSettingText = true
        textView.string = text
        coordinator.isSettingText = false
        coordinator.highlighter.rehighlight(storage)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        DispatchQueue.main.async { [weak textView] in
            textView?.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    static func makeTextSystem() -> (NSScrollView, EditorTextView) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = EditorTextView(frame: .zero, textContainer: container)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = true
        textView.textColor = EditorStyle.textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        textView.applyThemeColors()
        return (scrollView, textView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView, let storage = textView.textStorage else { return }
        #if DEBUG
        // TEMP DEBUG: a text mismatch here would overwrite the editor (and reset the selection).
        print("[Editor] updateNSView selection=\(NSStringFromRange(textView.selectedRange())) textInSync=\(textView.string == text) firstResponder=\(textView.window?.firstResponder === textView) editable=\(textView.isEditable)")
        #endif
        navigator?.textView = textView

        if scrollView.appearance?.name != theme.appearance?.name {
            // Scoped to the editor so it switches even before NSApp.appearance propagates.
            scrollView.appearance = theme.appearance
            textView.applyThemeColors()
        }

        textView.focusScope = behavior.focusScope
        textView.focusMode = behavior.focusMode
        textView.typewriterScrolling = behavior.typewriterScrolling

        if coordinator.highlighter.mode != mode || coordinator.highlighter.scale != zoom {
            coordinator.highlighter.setMode(mode, scale: zoom, in: storage)
            textView.columnWidth = coordinator.highlighter.style.columnWidth
            textView.typingAttributes = coordinator.highlighter.style.baseAttributes
            // Keep the caret in view after the layout has been rescaled.
            if textView.typewriterScrolling { textView.centerCaretLine() } else { textView.scrollRangeToVisible(textView.selectedRange()) }
        }

        if textView.string != text {
            let selection = textView.selectedRange()
            coordinator.isSettingText = true
            textView.string = text
            coordinator.isSettingText = false
            coordinator.highlighter.rehighlight(storage)
            let location = min(selection.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.updateCharacterHighlights()
        }
        textView.documentMode = mode
        textView.characterHighlights = characterHighlights
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptEditor
        let highlighter: SyntaxHighlighter
        weak var textView: EditorTextView?
        var isSettingText = false

        init(_ parent: ScriptEditor) {
            self.parent = parent
            self.highlighter = SyntaxHighlighter(mode: parent.mode)
        }

        func textDidChange(_ notification: Notification) {
            guard !isSettingText, let textView else { return }
            // An emptied document has no character to take typing attributes from: reset them here,
            // once the edit and the selection are settled, so the next keystroke is not a stale heading.
            if textView.textStorage?.length == 0 {
                textView.typingAttributes = highlighter.style.baseAttributes
            }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            #if DEBUG
            // TEMP DEBUG: trace selection changes while investigating the selection-delete freeze.
            print("[Editor] selection → \(NSStringFromRange(textView.selectedRange()))")
            #endif
            parent.navigator?.caretDidMove(to: textView.selectedRange().location)
        }

        #if DEBUG
        // TEMP DEBUG: trace replacements (typing, Backspace/Delete on a selection, cut, paste).
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            print("[Editor] shouldChangeText range=\(NSStringFromRange(affectedCharRange)) replacement=\(replacementString.map { "\($0.count) chars" } ?? "attributes only")")
            return true
        }
        #endif
    }
}
