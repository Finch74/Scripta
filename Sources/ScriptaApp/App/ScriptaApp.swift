import AppKit
import SwiftUI
import ScriptaCore

struct ScriptaApp: App {
    init() {
        let stored = UserDefaults.standard.string(forKey: AppTheme.storageKey)
        (stored.flatMap(AppTheme.init(rawValue:)) ?? .system).apply()
    }

    var body: some Scene {
        DocumentGroup(newDocument: ScriptaDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 980, height: 1040)
        .commands {
            // The default Edit menu is kept as-is: Cut/Copy/Paste/Select All are nil-targeted
            // and validated by AppKit, so they reach whichever NSTextView is first responder.
            ExportCommands()
            DocumentViewCommands()
            FormatCommands()
            WritingCommands()
            AppearanceCommands()
        }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.exportAction) private var exportAction

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Menu("Esporta") {
                Button("PDF…") { exportAction?.perform(.pdf) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("HTML…") { exportAction?.perform(.html) }
                Button("Markdown (.md)…") { exportAction?.perform(.markdown) }
                Button("Fountain (.fountain)…") { exportAction?.perform(.fountain) }
            }
            .disabled(exportAction == nil)
        }
    }
}
