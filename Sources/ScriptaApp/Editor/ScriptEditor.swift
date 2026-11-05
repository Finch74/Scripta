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

        let clipView = scrollView.contentView
        let maxY = max(0, frame.height - clipView.bounds.height)
        let targetY = min(maxY, max(0, floor(lineRect.midY + textContainerOrigin.y - clipView.bounds.height / 2)))
        guard abs(clipView.bounds.origin.y - targetY) >= 1 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
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
    
    func changeSpellCheckLanguage(to languageCode: String) {
        NSSpellChecker.shared.setLanguage(languageCode)
    }
}

/// Lets SwiftUI views (e.g. the outline sidebar) drive the caret of the AppKit editor.
@MainActor
final class EditorNavigator {
    fileprivate weak var textView: EditorTextView?

    /// Gives keyboard focus back to the editor (e.g. when leaving the preview).
    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Moves the caret to `location` and scrolls so that its line sits near the top of the editor.
    func reveal(location: Int) {
        guard let textView, let layoutManager = textView.layoutManager,
              let scrollView = textView.enclosingScrollView else { return }
        let location = min(max(0, location), (textView.string as NSString).length)
        let caret = NSRange(location: location, length: 0)

        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(caret)

        // Non-contiguous layout: make sure everything up to the target is laid out before measuring.
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: location))
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)

        let clipView = scrollView.contentView
        let maxY = max(0, textView.frame.height - clipView.bounds.height)
        let targetY = min(maxY, max(0, lineRect.minY + textView.textContainerOrigin.y - 24))
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)

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

        if let preferredLang = NSSpellChecker.shared.availableLanguages.first {
            NSSpellChecker.shared.setLanguage(preferredLang)
        }

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
            parent.text = textView.string
        }
    }
}
