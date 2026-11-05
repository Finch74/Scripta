import AppKit
import SwiftUI
import ScriptaCore

/// User-selectable appearance, persisted in UserDefaults under `AppTheme.storageKey`.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appTheme"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: "Sistema"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }

    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` follows the system setting.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the theme to the whole app (windows, menus, sheets and the AppKit editor).
    @MainActor
    func apply() {
        NSApp.appearance = appearance
    }
}

/// "Vista → Aspetto" menu.
struct AppearanceCommands: Commands {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Picker("Aspetto", selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.inline)
            // Applied by EditorView, which observes the same AppStorage key.
            Divider()
        }
    }
}
