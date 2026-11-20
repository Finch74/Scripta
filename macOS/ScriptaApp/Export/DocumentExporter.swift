import AppKit
import ScriptaCore

/// Single entry point for every export format.
@MainActor
enum DocumentExporter {
    static func export(text: String, mode: DocumentMode, format: ExportFormat,
                       options: ExportOptions, title: String, to url: URL) async throws {
        switch format {
        case .markdown, .fountain:
            try Data(text.utf8).write(to: url, options: .atomic)

        case .html:
            let result = HTMLRenderer.render(text: text, mode: mode, options: options,
                                             fallbackTitle: title, forPrint: false)
            try Data(result.html.utf8).write(to: url, options: .atomic)

        case .pdf:
            let result = HTMLRenderer.render(text: text, mode: mode, options: options,
                                             fallbackTitle: title, forPrint: true)
            let numbering = PageNumbering.standard(for: mode, hasTitlePage: result.hasTitlePage)
            try await PDFExporter().export(html: result.html, to: url,
                                           layout: .layout(for: mode, paper: options.paper),
                                           numbering: numbering,
                                           metadata: PDFMetadata(title: result.title, author: result.author))
        }
    }
}

/// Headless export used for automation and testing:
/// `Scripta --export <input> <output> [--mode screenplay|prose] [--paper letter|a4] [--notes]`
@MainActor
enum CommandLineExport {
    static func run(_ arguments: [String]) -> Never {
        guard let flag = arguments.firstIndex(of: "--export"), arguments.count > flag + 2 else {
            fail("Uso: Scripta --export <input> <output> [--mode screenplay|prose] [--paper letter|a4] [--notes]")
        }
        let input = URL(fileURLWithPath: arguments[flag + 1])
        let output = URL(fileURLWithPath: arguments[flag + 2])
        guard let format = ExportFormat(fileExtension: output.pathExtension) else {
            fail("Formato di output non supportato: .\(output.pathExtension)")
        }
        guard let data = try? Data(contentsOf: input) else { fail("Impossibile leggere \(input.path)") }
        let text = ScriptaDocument.decode(data)

        var mode: DocumentMode = ScriptaDocument.mode(forExtension: input.pathExtension, text: text)
        if let i = arguments.firstIndex(of: "--mode"), arguments.count > i + 1, let m = DocumentMode(rawValue: arguments[i + 1]) {
            mode = m
        }
        var options = ExportOptions.defaults(for: mode)
        if let i = arguments.firstIndex(of: "--paper"), arguments.count > i + 1, let p = PaperSize(rawValue: arguments[i + 1].lowercased()) {
            options.paper = p
        }
        options.includeNotes = arguments.contains("--notes")

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await DocumentExporter.export(text: text, mode: mode, format: format, options: options,
                                                  title: input.deletingPathExtension().lastPathComponent, to: output)
                print("Esportato: \(output.path)")
                exit(0)
            } catch {
                fail(error.localizedDescription)
            }
        }
        app.run()
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
