import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ScriptaCore

/// Shows the welcome window instead of an empty untitled document: at launch when no file is
/// opened, and when the Dock icon is clicked while no window is open.
///
/// DocumentGroup handles `applicationOpenUntitledFile` itself and does not forward it, so the
/// untitled document it creates at launch is replaced here once launching has finished.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Otherwise DocumentGroup opens an Open panel at launch instead of an untitled document.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files opened at launch (Finder, command line, restored windows) have a URL; the launch
        // untitled document is the only document when nothing else was opened.
        let documents = NSDocumentController.shared.documents
        guard !documents.isEmpty, documents.allSatisfy({ $0.fileURL == nil && !$0.isDocumentEdited }) else { return }
        documents.forEach { $0.close() }
        WelcomeWindowController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        WelcomeWindowController.show()
        return false
    }
}

/// "Archivio → Nuovo da modello…" (⌥⌘N) and "Finestra → Finestra di benvenuto" (⇧⌘1). Both work
/// with documents already open: they only bring the welcome window to the front.
struct WelcomeCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nuovo da modello…") { WelcomeWindowController.show(tab: .templates) }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .windowArrangement) {
            Button("Finestra di benvenuto") { WelcomeWindowController.show() }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Templates

/// A starting document offered by the welcome window, backed by a file of `Examples/`.
struct DocumentTemplate: Identifiable, Hashable {
    /// File name inside `Examples/`.
    let id: String
    let title: String
    let summary: String
    let symbolName: String

    /// Whether the template is a Fountain screenplay (Courier page) rather than Markdown prose.
    var isScreenplay: Bool { (id as NSString).pathExtension == "fountain" }

    static let scripts: [DocumentTemplate] = [
        DocumentTemplate(id: "Esempio_Cinematografico.fountain", title: "Sceneggiatura",
                         summary: "Cinema e TV in Fountain: scene INT./EXT., azione, personaggi, dialoghi e transizioni.",
                         symbolName: "film"),
        DocumentTemplate(id: "Esempio_GraphicNovel.fountain", title: "Graphic novel",
                         summary: "Fumetto per tavole e vignette, con descrizioni delle inquadrature, didascalie e balloon.",
                         symbolName: "square.grid.2x2"),
        DocumentTemplate(id: "Esempio.md", title: "Manoscritto / Romanzo",
                         summary: "Prosa in Markdown: capitoli, paragrafi, citazioni ed elenchi.",
                         symbolName: "book.closed"),
    ]

    /// The example file, if available: bundled by macOS/build-app.sh in Contents/Resources/Examples (or at the
    /// top of Resources) or, in debug builds run as a bare executable (swift run), the repository's Examples.
    var url: URL? {
        let name = (id as NSString).deletingPathExtension, ext = (id as NSString).pathExtension
        var candidates = [Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Examples"),
                          Bundle.main.url(forResource: name, withExtension: ext)]
        #if DEBUG
        // macOS/ScriptaApp/App/WelcomeWindow.swift → repository root.
        candidates.append(URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Examples").appendingPathComponent(id))
        #endif
        return candidates.compactMap { $0 }.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// The text the document starts with: the example file or, without it, `defaultText`.
    var text: String {
        url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? defaultText
    }

    /// Starting text used when the example file is missing (bare release executable, incomplete bundle),
    /// so that "Nuovo" always creates a document.
    var defaultText: String {
        switch id {
        case "Esempio_GraphicNovel.fountain":
            """
            Title: Titolo
            Credit: Sceneggiatura a fumetti di
            Author: Autore

            # Tav. 1

            .Vig. 1

            Descrizione della vignetta: inquadratura, ambiente, personaggi.

            Didascalia: testo della didascalia.

            **PERSONAGGIO**: Testo del balloon.

            .Vig. 2

            Descrizione della vignetta.

            """
        case "Esempio.md":
            """
            # Titolo del romanzo

            ## Capitolo 1

            Il testo del primo capitolo.

            """
        default:
            """
            Title: Titolo
            Credit: Scritto da
            Author: Autore

            FADE IN:

            INT. LUOGO - GIORNO

            Descrizione dell'azione.

            PERSONAGGIO
            Battuta del personaggio.

            CUT TO:

            """
        }
    }
}

// MARK: - Actions

/// Document actions of the welcome window, through NSDocumentController so they reach the
/// DocumentGroup's documents exactly like File → New / Open.
@MainActor
enum WelcomeActions {
    /// A new untitled document with the template's text: saving asks for a location, the example is never touched.
    /// Without the example file, the template's default text is written to a temporary file and used instead.
    static func newDocument(from template: DocumentTemplate) {
        var temporaryFolder: URL?
        defer { if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) } }
        do {
            let source: URL
            if let url = template.url {
                source = url
            } else {
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Scripta-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                temporaryFolder = folder
                // Same file name as the example, so the extension gives the document type (Fountain / Markdown).
                source = folder.appendingPathComponent(template.id)
                try Data(template.defaultText.utf8).write(to: source)
            }
            // `copying: true` is essential: with false AppKit *moves* the source into the autosave
            // location and deletes it when the untitled document is closed.
            _ = try NSDocumentController.shared.duplicateDocument(withContentsOf: source, copying: true, displayName: nil)
            WelcomeWindowController.close()
        } catch {
            NSApp.presentError(error)
        }
    }

    /// An empty untitled document of the default type, like File → New.
    static func newBlankDocument() {
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            WelcomeWindowController.close()
        } catch {
            NSApp.presentError(error)
        }
    }

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                NSApp.presentError(error)
            } else if document != nil {
                WelcomeWindowController.close()
            }
        }
    }

    static func showOpenPanel(for window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ScriptaDocument.readableContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            panel.urls.forEach(open)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }
}

// MARK: - Window

@MainActor
final class WelcomeWindowController: NSWindowController {
    private static var shared: WelcomeWindowController?
    private let model = WelcomeModel()

    /// Shows the window in front of any open document, on `tab` or, without one, on the recent files
    /// (the templates when there are none).
    static func show(tab: WelcomeModel.Tab? = nil) {
        let controller = shared ?? WelcomeWindowController()
        shared = controller
        controller.model.reload(tab: tab)
        controller.showWindow(nil)
        // Also when restored from the Dock or hidden behind document windows.
        if let window = controller.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        shared?.close()
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        window.title = "Benvenuto in Scripta"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        // One view for the window's lifetime, so reopening it never resizes or moves it.
        contentViewController = NSHostingController(rootView: WelcomeView(model: model))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - View

@MainActor
final class WelcomeModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case recent, templates

        var id: Self { self }

        var displayName: String {
            switch self {
            case .recent: "Recenti"
            case .templates: "Modelli"
            }
        }
    }

    @Published private(set) var recentURLs: [URL] = []
    @Published var tab: Tab = .templates
    /// No template is selected at first: "Apri modello" stays disabled until a card is clicked.
    @Published var selectedTemplate: DocumentTemplate.ID?
    @Published var selectedRecent: URL?

    /// Refreshes the recent files (they change while the window is closed) and picks the tab.
    func reload(tab requested: Tab?) {
        recentURLs = NSDocumentController.shared.recentDocumentURLs
        if selectedRecent.map({ !recentURLs.contains($0) }) ?? true { selectedRecent = recentURLs.first }
        tab = requested ?? (recentURLs.isEmpty ? .templates : .recent)
    }

    var template: DocumentTemplate? {
        DocumentTemplate.scripts.first { $0.id == selectedTemplate }
    }

    /// Page previews of the cards, parsed once: the example files do not change while the app runs.
    let previews: [DocumentTemplate.ID: [PreviewLine]] = Dictionary(
        uniqueKeysWithValues: DocumentTemplate.scripts.map { ($0.id, PreviewLine.lines(of: $0)) })
}

struct WelcomeView: View {
    /// Owned by WelcomeWindowController, which selects the tab when the window is reopened.
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                ForEach(WelcomeModel.Tab.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(12)

            Divider()

            switch model.tab {
            case .recent: recentList
            case .templates: templateList
            }

            Divider()

            HStack {
                Button(action: WelcomeActions.newBlankDocument) {
                    HStack(spacing: 6) {
                        Text("Nuovo")
                        Text("⌘N").opacity(0.7)
                    }
                    .padding(.horizontal, 6)
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Nuovo documento vuoto")

                Button("Apri…") { WelcomeActions.showOpenPanel(for: NSApp.keyWindow) }
                    .keyboardShortcut("o", modifiers: .command)

                Spacer()

                if model.tab == .templates {
                    Button("Apri modello") {
                        if let template = model.template { WelcomeActions.newDocument(from: template) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedTemplate == nil)
                    .help(model.template.map { "Nuovo documento dal modello \($0.title)" } ?? "Scegli un modello")
                }
            }
            .controlSize(.large)
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: Templates

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scegli un modello")
                    .font(.title2.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: TemplateCard.pageSize.width + 24), spacing: 20)],
                          alignment: .center, spacing: 20) {
                    ForEach(DocumentTemplate.scripts) { template in
                        TemplateCard(template: template, lines: model.previews[template.id] ?? [],
                                     isSelected: model.selectedTemplate == template.id)
                            // Double-click creates the document; the single click selects at once.
                            .onTapGesture(count: 2) { WelcomeActions.newDocument(from: template) }
                            .simultaneousGesture(TapGesture().onEnded { model.selectedTemplate = template.id })
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        // A click outside the cards clears the selection.
        .onTapGesture { model.selectedTemplate = nil }
    }

    // MARK: Recent files

    @ViewBuilder
    private var recentList: some View {
        if model.recentURLs.isEmpty {
            ContentUnavailableView {
                Label("Nessun documento recente", systemImage: "clock")
            } description: {
                Text("Crea un documento da un modello o apri un file esistente.")
            } actions: {
                Button("Mostra i modelli") { model.tab = .templates }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selectedRecent) {
                ForEach(model.recentURLs, id: \.self) { url in
                    RecentRow(url: url).tag(url)
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: URL.self) { urls in
                Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
            } primaryAction: { urls in
                urls.forEach(WelcomeActions.open)
            }
        }
    }
}

/// A template as a page thumbnail with its title centered below; the selected card has an accent ring.
struct TemplateCard: View {
    static let pageSize = CGSize(width: 150, height: 200)

    let template: DocumentTemplate
    let lines: [PreviewLine]
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            TemplatePage(lines: lines, isScreenplay: template.isScreenplay)
                .frame(width: Self.pageSize.width, height: Self.pageSize.height)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .padding(5)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }

            Text(template.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(isSelected ? Color.accentColor : .clear, in: Capsule())
        }
        .contentShape(Rectangle())
        .help(template.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(template.title)
        .accessibilityHint(template.summary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One line of a page preview: the parsed kind and its printable text.
struct PreviewLine: Identifiable {
    let id: Int
    let kind: LineKind
    let text: String

    /// The opening lines of the template laid out like the editor: title, headings, scenes, dialogue.
    /// Notes, synopses and the rest of the title page are left out; runs of blank lines become one.
    static func lines(of template: DocumentTemplate, limit: Int = 40) -> [PreviewLine] {
        let ns = template.text as NSString
        let parsed = template.isScreenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns)
        var result: [PreviewLine] = []
        for line in parsed where result.count < limit {
            switch line.kind {
            case .titleField("title"), .sceneHeading, .action, .character, .parenthetical,
                 .dialogue, .transition, .centered, .lyrics, .heading, .paragraph, .blockquote, .bullet, .ordered,
                 .code, .graphicNovelPage, .panel, .balloon:
                let text = ns.substring(with: line.textRange).replacingOccurrences(of: "*", with: "")
                result.append(PreviewLine(id: result.count, kind: line.kind, text: text))
            case .empty:
                if let last = result.last, last.kind != .empty {
                    result.append(PreviewLine(id: result.count, kind: .empty, text: ""))
                }
            default:
                continue
            }
        }
        return result
    }
}

/// A miniature white page: Courier for screenplays, serif for prose, clipped at the bottom edge.
struct TemplatePage: View {
    let lines: [PreviewLine]
    let isScreenplay: Bool

    private let fontSize: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines) { line in
                row(line)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.black.opacity(0.8))
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .environment(\.colorScheme, .light)
    }

    private func font(_ scale: CGFloat = 1, weight: Font.Weight = .regular) -> Font {
        isScreenplay ? .custom("Courier", size: fontSize * scale).weight(weight)
                     : .system(size: fontSize * scale, weight: weight, design: .serif)
    }

    @ViewBuilder
    private func row(_ line: PreviewLine) -> some View {
        let text = Text(line.text).lineLimit(3)
        switch line.kind {
        case .empty:
            Color.clear.frame(height: fontSize * 0.6)
        case .titleField:
            text.font(font(1.6, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 8)
        case .heading(let level):
            text.font(font(level == 1 ? 1.8 : 1.3, weight: .bold))
                .frame(maxWidth: .infinity, alignment: level == 1 ? .center : .leading)
        case .sceneHeading, .graphicNovelPage:
            text.font(font(weight: .bold))
        case .panel:
            text.font(font(weight: .semibold)).underline()
        case .character:
            text.font(font()).padding(.leading, 44)
        case .parenthetical:
            text.font(font()).padding(.leading, 34)
        case .dialogue:
            text.font(font()).padding(.horizontal, 22)
        case .transition:
            text.font(font()).frame(maxWidth: .infinity, alignment: .trailing)
        case .centered:
            text.font(font()).frame(maxWidth: .infinity)
        case .blockquote, .balloon:
            text.font(font()).italic(line.kind == .blockquote).padding(.leading, 10)
        case .bullet, .ordered:
            Text("•  " + line.text).font(font()).lineLimit(3).padding(.leading, 6)
        default:
            text.font(font())
        }
    }
}

struct RecentRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.headline)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .help(url.path)
    }
}
