import CGtk
import Foundation

/// `scripta-gtk`: the native Linux GUI of Scripta, built on GTK 4 and ScriptaCore.
///
/// Every file passed on the command line (or by the desktop environment, via the .desktop file)
/// opens in its own window; without files, an empty window is shown.

let applicationID = "io.github.finch74.Scripta"
let version = "1.0.0"

let application = raw(gtk_application_new(applicationID, scripta_application_flags()))!

@MainActor
func newWindow() -> ScriptaWindow {
    ScriptaWindow(application: application)
}

connect(application, "startup") {
    gtk_window_set_default_icon_name(applicationID)

    addAction(to: application, "new") { newWindow().present() }
    addAction(to: application, "about") { showAbout() }
    addAction(to: application, "quit") {
        // Closing each window goes through its unsaved-changes check.
        var windows: [Object] = []
        var node = gtk_application_get_windows(cast(application))
        while let current = node {
            if let window = current.pointee.data { windows.append(window) }
            node = current.pointee.next
        }
        windows.forEach { gtk_window_close(cast($0)) }
    }

    setAccelerators(application, "app.new", ["<Control>n"])
    setAccelerators(application, "app.quit", ["<Control>q"])
    setAccelerators(application, "win.open", ["<Control>o"])
    setAccelerators(application, "win.save", ["<Control>s"])
    setAccelerators(application, "win.save-as", ["<Control><Shift>s"])
    setAccelerators(application, "win.export-pdf", ["<Control><Shift>e"])
}

connect(application, "activate") {
    newWindow().present()
}

connectOpen(application) { paths in
    for path in paths {
        let window = newWindow()
        window.load(path)
        window.present()
    }
}

@MainActor
func showAbout() {
    let about = raw(gtk_about_dialog_new())!
    gtk_about_dialog_set_program_name(cast(about), "Scripta")
    gtk_about_dialog_set_version(cast(about), version)
    gtk_about_dialog_set_comments(cast(about), "Sceneggiature (Fountain), prosa (Markdown) e script per fumetti.")
    gtk_about_dialog_set_website(cast(about), "https://github.com/Finch74/Scripta")
    gtk_about_dialog_set_logo_icon_name(cast(about), applicationID)
    gtk_about_dialog_set_copyright(cast(about), "© 2026 Finch74")
    // The exact text of LICENSE (License.swift), shown under the dialog's license button.
    gtk_about_dialog_set_license(cast(about), licenseText)
    gtk_about_dialog_set_wrap_license(cast(about), 1)
    if let window = gtk_application_get_active_window(cast(application)) {
        gtk_window_set_transient_for(cast(about), window)
        gtk_window_set_modal(cast(about), 1)
    }
    gtk_window_present(cast(about))
}

// Headless export, as in the macOS app: `scripta-gtk --export <input> <output.pdf> [--paper letter|a4] [--notes]`.
if CommandLine.arguments.contains("--export") {
    MainActor.assumeIsolated { CommandLineExport.run(CommandLine.arguments) }
}

let status = g_application_run(cast(application), CommandLine.argc, CommandLine.unsafeArgv)
g_object_unref(application)
exit(status)
