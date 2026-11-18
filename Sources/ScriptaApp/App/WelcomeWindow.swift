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

    /// The example file, if available: bundled by build-app.sh in Contents/Resources/Examples (or at the
    /// top of Resources) or, in debug builds run as a bare executable (swift run), the repository's Examples.
    var url: URL? {
        let name = (id as NSString).deletingPathExtension, ext = (id as NSString).pathExtension
        var candidates = [Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Examples"),
                          Bundle.main.url(forResource: name, withExtension: ext)]
        #if DEBUG
        // Sources/ScriptaApp/App/WelcomeWindow.swift → repository root.
        candidates.append(URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Examples").appendingPathComponent(id))
        #endif
        return candidates.compactMap { $0 }.first { FileManager.default.isReadableFile(atPath: $0.path) }
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
    @Published var selectedTemplate: DocumentTemplate.ID? = DocumentTemplate.scripts.first?.id
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
                Button {
                    if let template = model.template { WelcomeActions.newDocument(from: template) }
                } label: {
                    HStack(spacing: 6) {
                        Text("Nuovo")
                        Text("⌘N").opacity(0.7)
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(model.template == nil)
                .help(model.template.map { "Nuovo documento dal modello \($0.title)" } ?? "Scegli un modello")

                Spacer()

                Button("Apri…") { WelcomeActions.showOpenPanel(for: NSApp.keyWindow) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            .controlSize(.large)
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    // MARK: Templates

    private var templateList: some View {
        List(selection: $model.selectedTemplate) {
            Section("SCRIPT") {
                ForEach(DocumentTemplate.scripts) { template in
                    TemplateRow(template: template).tag(template.id)
                }
            }
        }
        .listStyle(.inset)
        // Double-click or Return creates the document.
        .contextMenu(forSelectionType: DocumentTemplate.ID.self) { _ in } primaryAction: { ids in
            if let id = ids.first, let template = DocumentTemplate.scripts.first(where: { $0.id == id }) {
                WelcomeActions.newDocument(from: template)
            }
        }
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

struct TemplateRow: View {
    let template: DocumentTemplate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.symbolName)
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title).font(.headline)
                Text(template.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
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
