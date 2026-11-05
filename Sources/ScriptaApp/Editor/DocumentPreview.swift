import AppKit
import SwiftUI
import WebKit
import ScriptaCore

enum EditorViewMode: String, CaseIterable, Identifiable {
    case edit, preview

    var id: Self { self }

    var displayName: String {
        switch self {
        case .edit: "Modifica"
        case .preview: "Anteprima"
        }
    }

    var symbolName: String {
        switch self {
        case .edit: "pencil"
        case .preview: "eye"
        }
    }
}

/// Read-only formatted preview: the same HTML (and stylesheet) used by the HTML/PDF export,
/// shown as a paper sheet in a WKWebView.
struct DocumentPreview: NSViewRepresentable {
    let html: String

    final class Coordinator {
        var loadedHTML: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsMagnification = true
        load(webView, context: context)
        // Take keyboard focus from the (hidden) editor so typing cannot modify the document.
        DispatchQueue.main.async { [weak webView] in
            webView?.window?.makeFirstResponder(webView)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        load(webView, context: context)
    }

    private func load(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Menu commands

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<EditorViewMode>
}

struct ShowCharactersKey: FocusedValueKey {
    typealias Value = ShowCharactersAction
}

struct ShowCharactersAction {
    let perform: @MainActor () -> Void
}

extension FocusedValues {
    var viewMode: Binding<EditorViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }

    var showCharacters: ShowCharactersAction? {
        get { self[ShowCharactersKey.self] }
        set { self[ShowCharactersKey.self] = newValue }
    }
}

/// "Vista": Edit / Preview switch and the character analysis sheet.
struct DocumentViewCommands: Commands {
    @FocusedValue(\.viewMode) private var viewMode
    @FocusedValue(\.showCharacters) private var showCharacters

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button(viewMode?.wrappedValue == .preview ? "Torna all'editor" : "Mostra anteprima") {
                guard let viewMode else { return }
                viewMode.wrappedValue = viewMode.wrappedValue == .preview ? .edit : .preview
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(viewMode == nil)
            Button("Personaggi e analisi di genere…") { showCharacters?.perform() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(showCharacters == nil)
            Divider()
        }
    }
}
