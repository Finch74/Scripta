import SwiftUI
import ScriptaCore

/// UserDefaults keys for the writing preferences (shared by the View menu and the status bar).
enum PreferenceKey {
    static let typewriterScrolling = "typewriterScrolling"
    static let focusMode = "focusMode"
    static let focusScope = "focusScope"
    static let goalUnit = "goalUnit"
    static let goalTarget = "goalTarget"
    static let editorZoom = "editorZoom"
}

/// Text zoom of the editor, stored as a scale factor (1 = 100%).
enum EditorZoom {
    static let steps: [Double] = [0.5, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    static let range = 0.5...3.0

    static var current: Double {
        let value = UserDefaults.standard.double(forKey: PreferenceKey.editorZoom)
        return value == 0 ? 1 : value
    }

    static func set(_ value: Double) {
        UserDefaults.standard.set(min(max(value, range.lowerBound), range.upperBound), forKey: PreferenceKey.editorZoom)
    }

    static func zoomIn() {
        set(steps.first { $0 > current + 0.001 } ?? range.upperBound)
    }

    static func zoomOut() {
        set(steps.last { $0 < current - 0.001 } ?? range.lowerBound)
    }

    static func label(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// Portion of text kept in evidence by focus mode.
enum FocusScope: String, CaseIterable, Identifiable {
    case line, paragraph

    var id: Self { self }

    var displayName: String {
        switch self {
        case .line: "Riga"
        case .paragraph: "Paragrafo"
        }
    }
}

/// Behaviour switches forwarded to the AppKit editor.
struct EditorBehavior: Equatable {
    var typewriterScrolling = false
    var focusMode = false
    var focusScope: FocusScope = .paragraph
}

/// Writing goal, measured in words or (estimated) pages.
enum GoalUnit: String, CaseIterable, Identifiable {
    case none, words, pages

    var id: Self { self }

    var displayName: String {
        switch self {
        case .none: "Nessuno"
        case .words: "Parole"
        case .pages: "Pagine"
        }
    }

    var defaultTarget: Int {
        switch self {
        case .none: 0
        case .words: 1000
        case .pages: 10
        }
    }
}

/// "Vista" menu: typewriter scrolling, focus mode and writing goal.
struct WritingCommands: Commands {
    @AppStorage(PreferenceKey.typewriterScrolling) private var typewriterScrolling = false
    @AppStorage(PreferenceKey.focusMode) private var focusMode = false
    @AppStorage(PreferenceKey.focusScope) private var focusScope: FocusScope = .paragraph
    @AppStorage(PreferenceKey.goalUnit) private var goalUnit: GoalUnit = .none
    @AppStorage(PreferenceKey.goalTarget) private var goalTarget = 0
    @AppStorage(PreferenceKey.editorZoom) private var zoom = 1.0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Ingrandisci") { EditorZoom.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoom >= EditorZoom.range.upperBound)
            Button("Riduci") { EditorZoom.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom <= EditorZoom.range.lowerBound)
            Button("Dimensioni reali") { EditorZoom.set(1) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom == 1)
            Picker("Zoom (\(EditorZoom.label(zoom)))", selection: $zoom) {
                ForEach(EditorZoom.steps, id: \.self) { Text(EditorZoom.label($0)).tag($0) }
            }
            Divider()
            Toggle("Scorrimento a macchina da scrivere", isOn: $typewriterScrolling)
                .keyboardShortcut("t", modifiers: [.command, .control])
            Toggle("Modalità Focus", isOn: $focusMode)
                .keyboardShortcut("o", modifiers: [.command, .control])
            Picker("Evidenzia in Focus", selection: $focusScope) {
                ForEach(FocusScope.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Obiettivo di scrittura", selection: Binding(
                get: { goalUnit },
                set: { unit in
                    if unit != goalUnit { goalTarget = unit.defaultTarget }
                    goalUnit = unit
                })) {
                ForEach(GoalUnit.allCases) { Text($0.displayName).tag($0) }
            }
            Divider()
        }
    }
}
