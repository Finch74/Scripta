import CGtk
import Foundation
import ScriptaCore

/// One document window: header bar, sidebar (outline, characters, statistics) and the editor.
///
/// The instance is owned by its GtkApplicationWindow (via `g_object_set_data_full`) and lives
/// exactly as long as the window does.
@MainActor
final class ScriptaWindow {
    let window: Object
    private let textView: Object
    private let buffer: Object
    private let modeDropDown: Object
    private let outlineList: Object
    private let castList: Object
    private let statsList: Object
    private let statusLabel: Object
    private let highlighter: Highlighter

    private var path: String?
    private var mode: DocumentMode = .screenplay
    /// Character offsets of the outline rows, in row order.
    private var outlineOffsets: [Int32] = []
    private var pendingRefresh: guint = 0

    init(application: Object) {
        window = raw(gtk_application_window_new(cast(application)))!
        gtk_window_set_default_size(cast(window), 1100, 760)

        // Editor
        textView = raw(gtk_text_view_new())!
        buffer = raw(gtk_text_view_get_buffer(cast(textView)))!
        gtk_text_view_set_wrap_mode(cast(textView), GTK_WRAP_WORD_CHAR)
        gtk_text_view_set_left_margin(cast(textView), Highlighter.baseMargin)
        gtk_text_view_set_right_margin(cast(textView), Highlighter.baseMargin)
        gtk_text_view_set_top_margin(cast(textView), 32)
        gtk_text_view_set_bottom_margin(cast(textView), 32)
        gtk_text_view_set_pixels_below_lines(cast(textView), 2)
        highlighter = Highlighter(buffer: buffer)

        let editorScroll = raw(gtk_scrolled_window_new())!
        gtk_scrolled_window_set_child(cast(editorScroll), cast(textView))
        gtk_widget_set_vexpand(cast(editorScroll), 1)

        statusLabel = makeLabel("", cssClass: "dim-label")
        statusLabel.setMargins(top: 6, bottom: 6, start: 12, end: 12)

        let editorBox = raw(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))!
        gtk_box_append(cast(editorBox), cast(editorScroll))
        gtk_box_append(cast(editorBox), cast(raw(gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))))
        gtk_box_append(cast(editorBox), cast(statusLabel))

        // Sidebar
        outlineList = Self.makeList(placeholder: "Nessuna scena o titolo")
        castList = Self.makeList(placeholder: "Nessun personaggio")
        statsList = Self.makeList(placeholder: nil)
        gtk_list_box_set_selection_mode(cast(castList), GTK_SELECTION_NONE)
        gtk_list_box_set_selection_mode(cast(statsList), GTK_SELECTION_NONE)

        let stack = raw(gtk_stack_new())!
        gtk_widget_set_vexpand(cast(stack), 1)
        for (list, name, title) in [(outlineList, "outline", "Outline"), (castList, "cast", "Personaggi"),
                                    (statsList, "stats", "Statistiche")] {
            let scroll = raw(gtk_scrolled_window_new())!
            gtk_scrolled_window_set_policy(cast(scroll), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
            gtk_scrolled_window_set_child(cast(scroll), cast(list))
            gtk_stack_add_titled(cast(stack), cast(scroll), name, title)
        }
        let switcher = raw(gtk_stack_switcher_new())!
        gtk_stack_switcher_set_stack(cast(switcher), cast(stack))
        gtk_widget_set_halign(cast(switcher), GTK_ALIGN_CENTER)
        switcher.setMargins(top: 8, bottom: 8, start: 8, end: 8)

        let sidebar = raw(gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))!
        gtk_box_append(cast(sidebar), cast(switcher))
        gtk_box_append(cast(sidebar), cast(stack))

        let paned = raw(gtk_paned_new(GTK_ORIENTATION_HORIZONTAL))!
        gtk_paned_set_start_child(cast(paned), cast(sidebar))
        gtk_paned_set_end_child(cast(paned), cast(editorBox))
        gtk_paned_set_resize_start_child(cast(paned), 0)
        gtk_paned_set_shrink_start_child(cast(paned), 0)
        gtk_paned_set_position(cast(paned), 270)
        gtk_window_set_child(cast(window), cast(paned))

        // Header bar
        let header = raw(gtk_header_bar_new())!
        for (icon, action, tooltip) in [("document-new-symbolic", "app.new", "Nuova finestra (Ctrl+N)"),
                                        ("document-open-symbolic", "win.open", "Apri (Ctrl+O)"),
                                        ("document-save-symbolic", "win.save", "Salva (Ctrl+S)")] {
            let button = raw(gtk_button_new_from_icon_name(icon))!
            gtk_actionable_set_action_name(cast(button), action)
            gtk_widget_set_tooltip_text(cast(button), tooltip)
            gtk_header_bar_pack_start(cast(header), cast(button))
        }

        let menu = g_menu_new()
        g_menu_append(menu, "Nuova finestra", "app.new")
        g_menu_append(menu, "Salva con nome…", "win.save-as")
        g_menu_append(menu, "Informazioni su Scripta", "app.about")
        g_menu_append(menu, "Esci", "app.quit")
        let menuButton = raw(gtk_menu_button_new())!
        gtk_menu_button_set_icon_name(cast(menuButton), "open-menu-symbolic")
        gtk_menu_button_set_menu_model(cast(menuButton), cast(raw(menu)))
        g_object_unref(raw(menu))
        gtk_header_bar_pack_end(cast(header), cast(menuButton))

        let modeNames = DocumentMode.allCases.map { strdup($0.displayName) }
        modeDropDown = raw(gtk_drop_down_new_from_strings(modeNames.map { UnsafePointer($0) } + [nil]))!
        modeNames.forEach { free($0) }
        gtk_widget_set_tooltip_text(cast(modeDropDown), "Modalità di scrittura")
        gtk_header_bar_pack_end(cast(header), cast(modeDropDown))
        gtk_window_set_titlebar(cast(window), cast(header))

        // Ownership: the GtkWindow keeps this controller alive until it is finalized.
        g_object_set_data_full(cast(window), "scripta-window", Unmanaged.passRetained(self).toOpaque()) { data in
            guard let data else { return }
            Unmanaged<AnyObject>.fromOpaque(data).release()
        }

        addAction(to: window, "open") { [self] in confirmDiscard { self.chooseFileToOpen() } }
        addAction(to: window, "save") { [self] in save() }
        addAction(to: window, "save-as") { [self] in saveAs() }

        connect(buffer, "changed") { [self] in scheduleRefresh() }
        connect(buffer, "modified-changed") { [self] in updateTitle() }
        connect(modeDropDown, "notify::selected") { [self] (_: Object?) in
            let selected = Int(gtk_drop_down_get_selected(cast(modeDropDown)))
            guard DocumentMode.allCases.indices.contains(selected), DocumentMode.allCases[selected] != mode else { return }
            setMode(DocumentMode.allCases[selected])
        }
        connect(outlineList, "row-activated") { [self] (row: Object?) in
            let index = Int(gtk_list_box_row_get_index(cast(row)))
            guard outlineOffsets.indices.contains(index) else { return }
            jump(to: outlineOffsets[index])
        }
        connectReturningBool(window, "close-request") { [self] in
            guard isModified else { return false }
            confirmDiscard { gtk_window_destroy(cast(self.window)) }
            return true
        }
        connect(window, "destroy") { [self] in
            if pendingRefresh != 0 { g_source_remove(pendingRefresh) }
            pendingRefresh = 0
        }

        setMode(.screenplay)
        updateTitle()
    }

    func present() {
        gtk_window_present(cast(window))
        gtk_widget_grab_focus(cast(textView))
    }

    // MARK: - Document

    private var text: String {
        var start = GtkTextIter(), end = GtkTextIter()
        gtk_text_buffer_get_bounds(cast(buffer), &start, &end)
        guard let chars = gtk_text_buffer_get_text(cast(buffer), &start, &end, 1) else { return "" }
        defer { g_free(chars) }
        return String(cString: chars)
    }

    private var isModified: Bool { gtk_text_buffer_get_modified(cast(buffer)) != 0 }

    private var displayName: String {
        path.map { ($0 as NSString).lastPathComponent } ?? "Senza titolo"
    }

    /// Loads a file into this window, replacing the current text (without asking).
    func load(_ path: String) {
        guard let data = FileManager.default.contents(atPath: path) else {
            showError("Impossibile aprire «\((path as NSString).lastPathComponent)»", detail: path)
            return
        }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        self.path = path
        // Loading is not an edit: keep it out of the undo history and of the modified state.
        gtk_text_buffer_begin_irreversible_action(cast(buffer))
        gtk_text_buffer_set_text(cast(buffer), text, -1)
        gtk_text_buffer_end_irreversible_action(cast(buffer))
        gtk_text_buffer_set_modified(cast(buffer), 0)

        var start = GtkTextIter()
        gtk_text_buffer_get_start_iter(cast(buffer), &start)
        gtk_text_buffer_place_cursor(cast(buffer), &start)

        setMode(.inferred(fromExtension: (path as NSString).pathExtension, text: text))
        updateTitle()
    }

    private func setMode(_ newMode: DocumentMode) {
        mode = newMode
        let index = guint(DocumentMode.allCases.firstIndex(of: newMode) ?? 0)
        if gtk_drop_down_get_selected(cast(modeDropDown)) != index {
            gtk_drop_down_set_selected(cast(modeDropDown), index)
        }
        // Screenplays are traditionally typed in Courier.
        gtk_text_view_set_monospace(cast(textView), newMode == .screenplay ? 1 : 0)
        refresh()
    }

    private func updateTitle() {
        let title = (isModified ? "• " : "") + displayName + " — Scripta"
        gtk_window_set_title(cast(window), title)
    }

    // MARK: - Analysis

    /// Re-parsing is linear and cheap, but is coalesced while the user types.
    private func scheduleRefresh() {
        if pendingRefresh != 0 { g_source_remove(pendingRefresh) }
        pendingRefresh = after(milliseconds: 150) { [self] in
            pendingRefresh = 0
            refresh()
        }
    }

    private func refresh() {
        let text = text
        let map = highlighter.apply(text: text, mode: mode)
        let stats = DocumentStatistics(text: text, mode: mode)

        removeAllRows(outlineList)
        outlineOffsets = stats.outline.map { map.characterOffset($0.location) }
        for item in stats.outline {
            let label = switch item.kind {
            case .scene(let number): "\(number). \(item.title)"
            case .section: "§ \(item.title)"
            case .heading: item.title
            case .page: "▣ \(item.title)"
            case .panel: "▢ \(item.title)"
            }
            let row = makeLabel(label, cssClass: item.level == 0 ? "heading" : nil)
            row.setMargins(top: 6, bottom: 6, start: 12 + Int32(min(item.level, 6)) * 14, end: 12)
            gtk_list_box_append(cast(outlineList), cast(row))
        }

        removeAllRows(castList)
        for stat in stats.cast {
            let box = raw(gtk_box_new(GTK_ORIENTATION_VERTICAL, 2))!
            box.setMargins(top: 6, bottom: 6, start: 12, end: 12)
            gtk_box_append(cast(box), cast(makeLabel(stat.name, cssClass: "heading")))
            let detail = "\(stat.speeches) battute · \(stat.words) parole (\(String(format: "%.1f", stats.share(of: stat)))%)"
            gtk_box_append(cast(box), cast(makeLabel(detail, cssClass: "dim-label")))
            gtk_list_box_append(cast(castList), cast(box))
        }

        removeAllRows(statsList)
        for (label, value) in statisticsRows(stats) {
            let box = raw(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12))!
            box.setMargins(top: 6, bottom: 6, start: 12, end: 12)
            let name = makeLabel(label)
            gtk_widget_set_hexpand(cast(name), 1)
            gtk_box_append(cast(box), cast(name))
            gtk_box_append(cast(box), cast(makeLabel(value, cssClass: "numeric")))
            gtk_list_box_append(cast(statsList), cast(box))
        }

        var status = "\(stats.words) parole · \(stats.characterCount) caratteri"
        status += mode == .screenplay ? " · \(stats.scenes) scene" : " · ~\(stats.readingMinutes) min di lettura"
        gtk_label_set_text(cast(statusLabel), status)
    }

    /// Same rows as the STATISTICHE section of the `scripta` CLI.
    private func statisticsRows(_ stats: DocumentStatistics) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Modalità", stats.mode.displayName),
            ("Parole", "\(stats.words)"),
            ("Caratteri", "\(stats.characterCount)"),
            ("Righe non vuote", "\(stats.nonEmptyLines)"),
        ]
        if stats.mode == .screenplay {
            rows.append(("Scene", "\(stats.scenes)"))
            if stats.sections > 0 { rows.append(("Sezioni", "\(stats.sections)")) }
        } else {
            rows.append(("Titoli", "\(stats.headings)"))
            rows.append(("Tempo di lettura", "~\(stats.readingMinutes) min"))
        }
        if stats.pages > 0 || stats.panels > 0 {
            rows.append(("Tavole", "\(stats.pages)"))
            rows.append(("Vignette", "\(stats.panels)"))
        }
        if !stats.cast.isEmpty {
            rows.append(("Personaggi", "\(stats.cast.count)"))
            rows.append(("Battute", "\(stats.speeches)"))
            rows.append(("Righe di dialogo", "\(stats.dialogueLines)"))
        }
        return rows
    }

    private func jump(to offset: Int32) {
        var iter = GtkTextIter()
        gtk_text_buffer_get_iter_at_offset(cast(buffer), &iter, offset)
        gtk_text_buffer_place_cursor(cast(buffer), &iter)
        gtk_text_view_scroll_to_mark(cast(textView), gtk_text_buffer_get_insert(cast(buffer)), 0, 1, 0, 0.1)
        gtk_widget_grab_focus(cast(textView))
    }

    // MARK: - Files

    private func chooseFileToOpen() {
        chooseFile(GTK_FILE_CHOOSER_ACTION_OPEN, title: "Apri documento", accept: "_Apri") { [self] path in
            load(path)
        }
    }

    private func save(then proceed: (() -> Void)? = nil) {
        guard let path else {
            saveAs(then: proceed)
            return
        }
        if write(to: path) { proceed?() }
    }

    private func saveAs(then proceed: (() -> Void)? = nil) {
        let suggested = path.map { ($0 as NSString).lastPathComponent }
            ?? "Senza titolo." + (mode == .screenplay ? "fountain" : "md")
        chooseFile(GTK_FILE_CHOOSER_ACTION_SAVE, title: "Salva documento", accept: "_Salva",
                   suggestedName: suggested) { [self] path in
            guard write(to: path) else { return }
            self.path = path
            updateTitle()
            proceed?()
        }
    }

    private func write(to path: String) -> Bool {
        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            showError("Impossibile salvare «\((path as NSString).lastPathComponent)»", detail: error.localizedDescription)
            return false
        }
        gtk_text_buffer_set_modified(cast(buffer), 0)
        return true
    }

    private func chooseFile(_ action: GtkFileChooserAction, title: String, accept: String,
                            suggestedName: String? = nil, then handler: @escaping @MainActor (String) -> Void) {
        let dialog = raw(gtk_file_chooser_native_new(title, cast(window), action, accept, "_Annulla"))!
        gtk_native_dialog_set_modal(cast(dialog), 1)
        for (name, patterns) in [("Documenti Scripta", ["*.fountain", "*.spmd", "*.md", "*.markdown", "*.txt"]),
                                 ("Tutti i file", ["*"])] {
            let filter = raw(gtk_file_filter_new())!
            gtk_file_filter_set_name(cast(filter), name)
            patterns.forEach { gtk_file_filter_add_pattern(cast(filter), $0) }
            gtk_file_chooser_add_filter(cast(dialog), cast(filter))
            g_object_unref(filter)
        }
        if let suggestedName { gtk_file_chooser_set_current_name(cast(dialog), suggestedName) }

        connect(dialog, "response") { (response: Int32) in
            var path: String?
            if response == responseID(GTK_RESPONSE_ACCEPT), let file = gtk_file_chooser_get_file(cast(dialog)) {
                if let chars = g_file_get_path(file) {
                    path = String(cString: chars)
                    g_free(chars)
                }
                g_object_unref(raw(file))
            }
            g_object_unref(dialog)
            if let path { handler(path) }
        }
        gtk_native_dialog_show(cast(dialog))
    }

    // MARK: - Dialogs

    /// Runs `proceed` right away if there are no unsaved changes; otherwise asks first.
    private func confirmDiscard(_ proceed: @escaping @MainActor () -> Void) {
        guard isModified else {
            proceed()
            return
        }
        let dialog = raw(scripta_message_dialog_new(cast(window), GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
                                                    "Salvare le modifiche a «\(displayName)»?",
                                                    "Se non salvi, le modifiche andranno perse."))!
        gtk_dialog_add_button(cast(dialog), "_Annulla", responseID(GTK_RESPONSE_CANCEL))
        let discard = gtk_dialog_add_button(cast(dialog), "_Non salvare", responseID(GTK_RESPONSE_REJECT))
        gtk_widget_add_css_class(discard, "destructive-action")
        gtk_dialog_add_button(cast(dialog), "_Salva", responseID(GTK_RESPONSE_ACCEPT))
        gtk_dialog_set_default_response(cast(dialog), responseID(GTK_RESPONSE_ACCEPT))

        connect(dialog, "response") { [self] (response: Int32) in
            gtk_window_destroy(cast(dialog))
            switch response {
            case responseID(GTK_RESPONSE_ACCEPT): save(then: proceed)
            case responseID(GTK_RESPONSE_REJECT): proceed()
            default: break
            }
        }
        gtk_window_present(cast(dialog))
    }

    private func showError(_ message: String, detail: String) {
        let dialog = raw(scripta_message_dialog_new(cast(window), GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, message, detail))!
        connect(dialog, "response") { (_: Int32) in gtk_window_destroy(cast(dialog)) }
        gtk_window_present(cast(dialog))
    }

    private static func makeList(placeholder: String?) -> Object {
        let list = raw(gtk_list_box_new())!
        list.addCSSClass("navigation-sidebar")
        if let placeholder {
            let label = raw(gtk_label_new(placeholder))!
            label.addCSSClass("dim-label")
            label.setMargins(top: 24, bottom: 24, start: 12, end: 12)
            gtk_list_box_set_placeholder(cast(list), cast(label))
        }
        return list
    }
}
