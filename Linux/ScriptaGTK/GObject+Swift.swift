import CGtk

/// Any GObject instance (widget, buffer, action…), kept untyped on the Swift side.
///
/// GTK's cast macros (GTK_WINDOW(), G_OBJECT()…) are not visible to Swift, and some GTK types are
/// imported as typed pointers while others are opaque. Instances are therefore stored as raw
/// pointers and reinterpreted with `cast(_:)`, whose result type is inferred from the C call.
typealias Object = UnsafeMutableRawPointer

@inline(__always) func cast<T>(_ object: Object?) -> UnsafeMutablePointer<T>? {
    object?.assumingMemoryBound(to: T.self)
}

@inline(__always) func cast(_ object: Object?) -> OpaquePointer? {
    object.map(OpaquePointer.init)
}

@inline(__always) func raw<T>(_ pointer: UnsafeMutablePointer<T>?) -> Object? {
    pointer.map(UnsafeMutableRawPointer.init)
}

@inline(__always) func raw(_ pointer: OpaquePointer?) -> Object? {
    pointer.map(UnsafeMutableRawPointer.init)
}

/// Response ids arrive as plain `gint` in the "response" signal.
func responseID(_ response: GtkResponseType) -> Int32 {
    Int32(truncatingIfNeeded: response.rawValue)
}

// MARK: - Signals

/// Holds a Swift closure for the lifetime of a signal connection or a main-loop source.
private final class Box<F> {
    let value: F
    init(_ value: F) { self.value = value }
}

private let releaseClosureBox: GClosureNotify = { data, _ in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

private let releaseBox: GDestroyNotify = { data in
    guard let data else { return }
    Unmanaged<AnyObject>.fromOpaque(data).release()
}

private func unbox<F>(_ data: gpointer?, as type: F.Type) -> F {
    Unmanaged<Box<F>>.fromOpaque(data!).takeUnretainedValue().value
}

@discardableResult
private func connect<F>(_ instance: Object, _ signal: String, _ trampoline: GCallback, _ handler: F) -> gulong {
    let data = Unmanaged.passRetained(Box(handler) as AnyObject).toOpaque()
    return g_signal_connect_data(instance, signal, trampoline, data, releaseClosureBox, GConnectFlags(rawValue: 0))
}

// GTK always emits signals on the main thread, which runs the GLib main loop.
// The trampolines take every pointer argument as `gpointer`: C ABI-wise they are all the same.

/// Signals of the form `void handler(GObject *self, gpointer data)`.
@MainActor @discardableResult
func connect(_ instance: Object, _ signal: String, _ handler: @escaping @MainActor () -> Void) -> gulong {
    let trampoline: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
        let handler = unbox(data, as: (@MainActor () -> Void).self)
        MainActor.assumeIsolated { handler() }
    }
    return connect(instance, signal, unsafeBitCast(trampoline, to: GCallback.self), handler)
}

/// Signals of the form `void handler(GObject *self, gpointer arg, gpointer data)`.
@MainActor @discardableResult
func connect(_ instance: Object, _ signal: String, _ handler: @escaping @MainActor (Object?) -> Void) -> gulong {
    let trampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { _, arg, data in
        let handler = unbox(data, as: (@MainActor (Object?) -> Void).self)
        nonisolated(unsafe) let arg = arg
        MainActor.assumeIsolated { handler(arg) }
    }
    return connect(instance, signal, unsafeBitCast(trampoline, to: GCallback.self), handler)
}

/// Signals of the form `void handler(GObject *self, gint arg, gpointer data)`, e.g. "response".
@MainActor @discardableResult
func connect(_ instance: Object, _ signal: String, _ handler: @escaping @MainActor (Int32) -> Void) -> gulong {
    let trampoline: @convention(c) (gpointer?, gint, gpointer?) -> Void = { _, arg, data in
        let handler = unbox(data, as: (@MainActor (Int32) -> Void).self)
        MainActor.assumeIsolated { handler(arg) }
    }
    return connect(instance, signal, unsafeBitCast(trampoline, to: GCallback.self), handler)
}

/// Signals of the form `gboolean handler(GObject *self, gpointer data)`, e.g. "close-request".
@MainActor @discardableResult
func connectReturningBool(_ instance: Object, _ signal: String, _ handler: @escaping @MainActor () -> Bool) -> gulong {
    let trampoline: @convention(c) (gpointer?, gpointer?) -> gboolean = { _, data in
        let handler = unbox(data, as: (@MainActor () -> Bool).self)
        return MainActor.assumeIsolated { handler() } ? 1 : 0
    }
    return connect(instance, signal, unsafeBitCast(trampoline, to: GCallback.self), handler)
}

/// The "open" signal of GApplication: `void handler(GApplication *, GFile **, gint, gchar *, gpointer)`.
@MainActor @discardableResult
func connectOpen(_ application: Object, _ handler: @escaping @MainActor ([String]) -> Void) -> gulong {
    let trampoline: @convention(c) (gpointer?, gpointer?, gint, gpointer?, gpointer?) -> Void = { _, files, count, _, data in
        let handler = unbox(data, as: (@MainActor ([String]) -> Void).self)
        guard let files = files?.assumingMemoryBound(to: OpaquePointer?.self) else { return }
        let paths = (0..<Int(count)).compactMap { index -> String? in
            guard let file = files[index], let path = g_file_get_path(file) else { return nil }
            defer { g_free(path) }
            return String(cString: path)
        }
        MainActor.assumeIsolated { handler(paths) }
    }
    return connect(application, "open", unsafeBitCast(trampoline, to: GCallback.self), handler)
}

/// Runs `handler` once on the main loop after `milliseconds`. Returns the source id.
@MainActor
func after(milliseconds: UInt32, _ handler: @escaping @MainActor () -> Void) -> guint {
    let trampoline: GSourceFunc = { data in
        let handler = unbox(data, as: (@MainActor () -> Void).self)
        MainActor.assumeIsolated { handler() }
        return 0 // G_SOURCE_REMOVE
    }
    let data = Unmanaged.passRetained(Box(handler) as AnyObject).toOpaque()
    return g_timeout_add_full(G_PRIORITY_DEFAULT, milliseconds, trampoline, data, releaseBox)
}

// MARK: - Actions

/// Adds a parameterless GAction named `name` to `map` (the application or a window).
@MainActor
func addAction(to map: Object, _ name: String, _ handler: @escaping @MainActor () -> Void) {
    let action = raw(g_simple_action_new(name, nil))!
    connect(action, "activate") { (_: Object?) in handler() }
    g_action_map_add_action(cast(map), cast(action))
    g_object_unref(action)
}

@MainActor
func setAccelerators(_ application: Object, _ action: String, _ accelerators: [String]) {
    let strings = accelerators.map { strdup($0) }
    defer { strings.forEach { free($0) } }
    let array = strings.map { UnsafePointer($0) } + [nil]
    gtk_application_set_accels_for_action(cast(application), action, array)
}

// MARK: - Widgets

extension UnsafeMutableRawPointer {
    /// `gtk_widget_*` helpers, so call sites read like the C API without the casts.
    @MainActor func addCSSClass(_ name: String) { gtk_widget_add_css_class(cast(self), name) }
    @MainActor func setMargins(top: Int32 = 0, bottom: Int32 = 0, start: Int32 = 0, end: Int32 = 0) {
        gtk_widget_set_margin_top(cast(self), top)
        gtk_widget_set_margin_bottom(cast(self), bottom)
        gtk_widget_set_margin_start(cast(self), start)
        gtk_widget_set_margin_end(cast(self), end)
    }
}

/// A left-aligned label.
@MainActor
func makeLabel(_ text: String, cssClass: String? = nil) -> Object {
    let label = raw(gtk_label_new(text))!
    gtk_label_set_xalign(cast(label), 0)
    gtk_label_set_ellipsize(cast(label), PANGO_ELLIPSIZE_END)
    if let cssClass { label.addCSSClass(cssClass) }
    return label
}

/// Removes every row of a GtkListBox (gtk_list_box_remove_all needs GTK 4.12).
@MainActor
func removeAllRows(_ list: Object) {
    while let child = gtk_widget_get_first_child(cast(list)) {
        gtk_list_box_remove(cast(list), child)
    }
}
