import CGtk
import Foundation
import ScriptaCore

/// `scripta-gtk --export <input> <output.pdf> [--mode screenplay|prose] [--paper letter|a4] [--notes]`:
/// exports without opening a window (a display is still needed, since WebKitGTK is a GTK widget).
@MainActor
enum CommandLineExport {
    static func run(_ arguments: [String]) -> Never {
        guard let flag = arguments.firstIndex(of: "--export"), arguments.count > flag + 2 else {
            fail("Uso: scripta-gtk --export <input> <output.pdf> [--mode screenplay|prose] [--paper letter|a4] [--notes]")
        }
        let input = URL(fileURLWithPath: arguments[flag + 1])
        let output = URL(fileURLWithPath: arguments[flag + 2])
        guard output.pathExtension.lowercased() == "pdf" else { fail("Formato di output non supportato: .\(output.pathExtension)") }
        guard let data = FileManager.default.contents(atPath: input.path) else { fail("Impossibile leggere \(input.path)") }
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var mode = DocumentMode.inferred(fromExtension: input.pathExtension, text: text)
        if let i = arguments.firstIndex(of: "--mode"), arguments.count > i + 1, let m = DocumentMode(rawValue: arguments[i + 1]) {
            mode = m
        }
        var options = ExportOptions.defaults(for: mode)
        if let i = arguments.firstIndex(of: "--paper"), arguments.count > i + 1,
           let p = PaperSize(rawValue: arguments[i + 1].lowercased()) {
            options.paper = p
        }
        options.includeNotes = arguments.contains("--notes")

        g_set_application_name("Scripta")
        gtk_init()
        let result = HTMLRenderer.render(text: text, mode: mode, options: options,
                                         fallbackTitle: input.deletingPathExtension().lastPathComponent, forPrint: true)
        let loop = g_main_loop_new(nil, 0)
        var failure: String?
        PDFExporter.export(html: result.html, to: output, layout: .layout(for: mode, paper: options.paper),
                           numbering: .standard(for: mode, hasTitlePage: result.hasTitlePage),
                           metadata: PDFMetadata(title: result.title, author: result.author)) { error in
            failure = error?.localizedDescription
            // Let the exporter tear down (and remove its temporary files) before quitting.
            _ = after(milliseconds: 10) { g_main_loop_quit(loop) }
        }
        g_main_loop_run(loop)
        if let failure { fail(failure) }
        print("Esportato: \(output.path)")
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
