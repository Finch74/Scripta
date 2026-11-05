import AppKit
import Combine
import SwiftUI
import ScriptaCore

struct ExportAction {
    let perform: @MainActor (ExportFormat) -> Void
}

struct ExportActionKey: FocusedValueKey {
    typealias Value = ExportAction
}

extension FocusedValues {
    var exportAction: ExportAction? {
        get { self[ExportActionKey.self] }
        set { self[ExportActionKey.self] = newValue }
    }
}

struct EditorView: View {
    @Binding var document: ScriptaDocument
    let fileURL: URL?

    @StateObject private var state: EditorState
    @StateObject private var characters: CharacterProfileStore
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @AppStorage(PreferenceKey.typewriterScrolling) private var typewriterScrolling = false
    @AppStorage(PreferenceKey.focusMode) private var focusMode = false
    @AppStorage(PreferenceKey.focusScope) private var focusScope: FocusScope = .paragraph
    @AppStorage(PreferenceKey.editorZoom) private var zoom = 1.0

    init(document: Binding<ScriptaDocument>, fileURL: URL?) {
        _document = document
        self.fileURL = fileURL
        let mode = document.wrappedValue.initialMode
        _state = StateObject(wrappedValue: EditorState(mode: mode))
        _characters = StateObject(wrappedValue: CharacterProfileStore(fileURL: fileURL))
    }

    private var mode: DocumentMode { state.mode }

    private var baseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Senza titolo"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $state.sidebarVisibility) {
            OutlineSidebar(items: DocumentOutline.items(in: document.text, mode: mode), mode: mode,
                           selection: $state.outlineSelection) { item in
                state.navigator.reveal(location: item.location)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
        } detail: {
            VStack(spacing: 0) {
                // The editor stays alive under the preview so undo, selection and scroll survive the switch.
                ZStack {
                    ScriptEditor(text: $document.text, mode: mode, theme: theme,
                                 behavior: EditorBehavior(typewriterScrolling: typewriterScrolling,
                                                          focusMode: focusMode, focusScope: focusScope),
                                 characterHighlights: characters.highlightColors,
                                 zoom: CGFloat(zoom), navigator: state.navigator)
                    if state.viewMode == .preview {
                        DocumentPreview(html: HTMLRenderer.render(text: document.text, mode: mode, options: state.options,
                                                                  fallbackTitle: baseName, forPrint: false).html)
                    }
                }
                Divider()
                StatusBar(statistics: TextStatistics(text: document.text, mode: mode), isExporting: state.isExporting,
                          theme: $theme, isEditingGoal: $state.isEditingGoal)
            }
            .background(Color(nsColor: EditorStyle.backgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Modalità", selection: $state.mode) {
                    ForEach(DocumentMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Sceneggiatura (Fountain) o prosa (Markdown)")
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Vista", selection: $state.viewMode) {
                    ForEach(EditorViewMode.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Modifica o anteprima formattata (⌥⌘P)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.isShowingCharacters = true
                } label: {
                    Label("Personaggi", systemImage: "person.2")
                }
                .help("Personaggi, battute e analisi di genere (⇧⌘K)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(formats) { format in
                        Button(format.menuTitle) { export(format) }
                    }
                    Divider()
                    Picker("Formato carta", selection: $state.options.paper) {
                        ForEach(PaperSize.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Includi note [[ ]]", isOn: $state.options.includeNotes)
                    if mode == .screenplay {
                        Toggle("Pagina del titolo", isOn: $state.options.includeTitlePage)
                        Toggle("Numeri di scena", isOn: $state.options.includeSceneNumbers)
                    }
                } label: {
                    Label("Esporta", systemImage: "square.and.arrow.up")
                }
                .disabled(state.isExporting)
                .help("Esporta in Markdown, HTML o PDF")
            }
        }
        .onAppear {
            // A bare executable (swift run) starts in the background: bring Scripta to the front
            // so macOS routes keyboard events (and the clipboard shortcuts) to its window.
            NSApplication.shared.activate(ignoringOtherApps: true)
            theme.apply()
        }
        .onChange(of: theme) { _, newTheme in newTheme.apply() }
        .onChange(of: state.mode) { _, newMode in
            state.options.paper = ExportOptions.defaults(for: newMode).paper
        }
        .onChange(of: state.viewMode) { _, newMode in
            if newMode == .edit { state.navigator.focus() }
        }
        .onChange(of: fileURL) { _, url in characters.rebind(to: url) }
        .sheet(isPresented: $state.isShowingCharacters) {
            CharacterAnalysisView(statistics: CharacterAnalysis.statistics(text: document.text, mode: mode), store: characters)
        }
        .focusedSceneValue(\.exportAction, ExportAction(perform: export))
        .focusedSceneValue(\.viewMode, $state.viewMode)
        .focusedSceneValue(\.documentMode, mode)
        .focusedSceneValue(\.showCharacters, ShowCharactersAction { [state] in state.isShowingCharacters = true })
        .alert("Esportazione non riuscita", isPresented: Binding(
            get: { state.exportError != nil }, set: { if !$0 { state.exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.exportError ?? "")
        }
    }

    private var formats: [ExportFormat] {
        mode == .screenplay ? [.pdf, .html, .fountain, .markdown] : [.pdf, .html, .markdown]
    }

    @MainActor
    private func export(_ format: ExportFormat) {
        guard !state.isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let directory = fileURL?.deletingLastPathComponent() { panel.directoryURL = directory }

        let text = document.text, mode = state.mode, options = state.options, title = baseName, state = state
        Task { @MainActor in
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return }
            state.isExporting = true
            defer { state.isExporting = false }
            do {
                try await DocumentExporter.export(text: text, mode: mode, format: format,
                                                  options: options, title: title, to: url)
            } catch {
                state.exportError = error.localizedDescription
            }
        }
    }
}

/// Per-window UI state (kept in an ObservableObject so it survives view updates).
@MainActor
final class EditorState: ObservableObject {
    @Published var mode: DocumentMode
    @Published var options: ExportOptions
    @Published var isExporting = false
    @Published var exportError: String?
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Published var outlineSelection: OutlineItem.ID?
    @Published var isEditingGoal = false
    @Published var viewMode: EditorViewMode = .edit
    @Published var isShowingCharacters = false
    let navigator = EditorNavigator()

    init(mode: DocumentMode) {
        self.mode = mode
        self.options = .defaults(for: mode)
    }
}

/// Navigable index of the document: scenes and sections (Fountain) or headings (Markdown).
struct OutlineSidebar: View {
    let items: [OutlineItem]
    let mode: DocumentMode
    @Binding var selection: OutlineItem.ID?
    let onSelect: (OutlineItem) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nessun indice", systemImage: "list.bullet.indent")
                } description: {
                    Text(mode == .screenplay
                         ? "Aggiungi intestazioni di scena (INT./EXT.) o sezioni (#)."
                         : "Aggiungi titoli con #.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(items) { item in
                        OutlineRow(item: item)
                            .tag(item.id)
                            .contentShape(Rectangle())
                            // A tap (not just a selection change) so re-clicking the same entry jumps again.
                            .onTapGesture {
                                selection = item.id
                                onSelect(item)
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Indice")
    }
}

struct OutlineRow: View {
    let item: OutlineItem

    var body: some View {
        HStack(spacing: 6) {
            switch item.kind {
            case .scene(let number):
                Text("\(number)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(item.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            case .section:
                Image(systemName: "number").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(item.title).font(.system(size: 12, weight: .semibold))
            case .heading:
                Text(item.title)
                    .font(.system(size: item.level == 0 ? 13 : 12, weight: item.level == 0 ? .semibold : .regular))
            case .page:
                Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(.secondary)
                Text(item.title).font(.system(size: 12, weight: .bold))
            case .panel:
                Image(systemName: "square.split.2x2").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text(item.title).font(.system(size: 12))
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.leading, CGFloat(min(item.level, 5)) * 12)
        .help(item.title)
    }
}

struct StatusBar: View {
    let statistics: TextStatistics
    let isExporting: Bool
    @Binding var theme: AppTheme
    /// A binding rather than @State: the Command Line Tools toolchain lacks the SwiftUI macro plugin.
    @Binding var isEditingGoal: Bool

    @AppStorage(PreferenceKey.typewriterScrolling) private var typewriterScrolling = false
    @AppStorage(PreferenceKey.focusMode) private var focusMode = false
    @AppStorage(PreferenceKey.goalUnit) private var goalUnit: GoalUnit = .none
    @AppStorage(PreferenceKey.goalTarget) private var goalTarget = 0
    @AppStorage(PreferenceKey.editorZoom) private var zoom = 1.0

    var body: some View {
        HStack(spacing: 16) {
            Text("\(statistics.words) parole")
            Text("\(statistics.characters) caratteri")
            if let scenes = statistics.scenes { Text("\(scenes) scene") }
            if let pages = statistics.pages { Text("≈ \(pages) pag.") }
            Text("\(statistics.durationLabel) \(statistics.formattedDuration)")
                .help(statistics.durationHelp)
            Spacer()
            if isExporting {
                ProgressView().controlSize(.small)
                Text("Esportazione…")
            }
            goalButton
            zoomMenu
            HStack(spacing: 10) {
                toggle(isOn: $typewriterScrolling, symbol: "character.cursor.ibeam",
                       help: "Scorrimento a macchina da scrivere (⌃⌘T)")
                toggle(isOn: $focusMode, symbol: "scope", help: "Modalità Focus (⌃⌘O)")
                Menu {
                    Picker("Aspetto", selection: $theme) {
                        ForEach(AppTheme.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: theme.symbolName)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Aspetto: \(theme.displayName)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(nsColor: EditorStyle.backgroundColor))
    }

    private var zoomMenu: some View {
        Menu {
            Button("Ingrandisci  ⌘+") { EditorZoom.zoomIn() }
            Button("Riduci  ⌘−") { EditorZoom.zoomOut() }
            Button("Dimensioni reali  ⌘0") { EditorZoom.set(1) }
            Divider()
            Picker("Zoom", selection: $zoom) {
                ForEach(EditorZoom.steps, id: \.self) { Text(EditorZoom.label($0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(EditorZoom.label(zoom)).monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Zoom del testo")
    }

    private func toggle(isOn: Binding<Bool>, symbol: String, help: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: symbol)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var goalProgress: Double? {
        guard goalUnit != .none, goalTarget > 0 else { return nil }
        let current = goalUnit == .words ? Double(statistics.words) : statistics.pageEstimate
        return current / Double(goalTarget)
    }

    private var goalButton: some View {
        Button { isEditingGoal = true } label: {
            if let progress = goalProgress {
                HStack(spacing: 6) {
                    ProgressView(value: min(progress, 1))
                        .progressViewStyle(.linear)
                        .tint(progress >= 1 ? .green : .accentColor)
                        .frame(width: 70)
                    Text(goalSummary(progress))
                        .monospacedDigit()
                    if progress >= 1 { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            } else {
                Image(systemName: "flag")
            }
        }
        .buttonStyle(.borderless)
        .help("Obiettivo di scrittura")
        .popover(isPresented: $isEditingGoal, arrowEdge: .top) {
            GoalEditor(unit: $goalUnit, target: $goalTarget)
        }
    }

    private func goalSummary(_ progress: Double) -> String {
        let current = goalUnit == .words
            ? statistics.words.formatted()
            : statistics.pageEstimate.formatted(.number.precision(.fractionLength(0...1)))
        let unit = goalUnit == .words ? "parole" : "pag."
        return "\(current) / \(goalTarget.formatted()) \(unit) · \(Int((progress * 100).rounded(.down)))%"
    }
}

/// Popover used to set the writing goal from the status bar.
struct GoalEditor: View {
    @Binding var unit: GoalUnit
    @Binding var target: Int

    var body: some View {
        Form {
            Picker("Obiettivo", selection: Binding(
                get: { unit },
                set: { newUnit in
                    if newUnit != unit { target = newUnit.defaultTarget }
                    unit = newUnit
                })) {
                ForEach(GoalUnit.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            if unit != .none {
                HStack {
                    TextField("Traguardo", value: $target, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $target, in: 1...1_000_000, step: unit == .words ? 100 : 1)
                        .labelsHidden()
                    Text(unit == .words ? "parole" : "pagine")
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .onChange(of: target) { _, value in
            if value < 1, unit != .none { target = 1 }
        }
    }
}

struct TextStatistics {
    /// Reading pace for prose; a screenplay page runs about one minute of screen time.
    static let wordsPerMinute: Double = 180
    /// Manuscript page used to estimate prose pages for the writing goal.
    static let wordsPerProsePage: Double = 250

    var words = 0
    var characters = 0
    var scenes: Int?
    var pages: Int?
    /// Fractional page count (screenplay layout or manuscript pages), used by the goal.
    var pageEstimate: Double = 0
    /// Estimated running time (screenplay) or reading time (prose).
    var minutes: Double = 0
    let mode: DocumentMode

    init(text: String, mode: DocumentMode) {
        self.mode = mode
        let ns = text as NSString
        characters = ns.length
        var count = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        words = count

        guard mode == .screenplay else {
            pageEstimate = Double(words) / Self.wordsPerProsePage
            minutes = Double(words) / Self.wordsPerMinute
            return
        }
        // Rough page estimate: ~55 printed lines per page, wrapped at the element's column width.
        var sceneCount = 0
        var printedLines = 0
        for line in FountainParser.parse(ns) {
            let width: Int
            switch line.kind {
            case .sceneHeading: sceneCount += 1; width = 60; printedLines += 1
            case .dialogue: width = 35
            case .parenthetical: width = 25
            case .empty: printedLines += 1; continue
            case .section, .synopsis, .boneyard, .note, .titleField: continue
            default: width = 60
            }
            printedLines += max(1, (line.textRange.length + width - 1) / width)
        }
        scenes = sceneCount
        pageEstimate = Double(printedLines) / 55
        pages = max(1, Int(pageEstimate.rounded(.up)))
        minutes = words == 0 ? 0 : pageEstimate
    }

    var durationLabel: String { mode == .screenplay ? "Durata" : "Lettura" }

    var durationHelp: String {
        mode == .screenplay
            ? "Durata stimata: 1 pagina ≈ 1 minuto"
            : "Tempo di lettura stimato a \(Int(Self.wordsPerMinute)) parole al minuto"
    }

    var formattedDuration: String {
        if minutes == 0 { return "0 min" }
        if minutes < 1 { return "< 1 min" }
        let total = Int(minutes.rounded())
        return total < 60 ? "≈ \(total) min" : "≈ \(total / 60) h \(String(format: "%02d", total % 60)) min"
    }
}
