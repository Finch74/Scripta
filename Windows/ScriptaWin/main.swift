import Foundation
import ScriptaCore

/// `ScriptaWin`: starting point of the Windows front end. For now a console program that, given a
/// Fountain or Markdown file, prints its statistics with ScriptaCore; the GUI will be built on top.

let usage = """
    Uso: ScriptaWin <file.fountain|file.md>

    Front end Windows di Scripta (anteprima a riga di comando).
    """

let arguments = Array(CommandLine.arguments.dropFirst())

guard let path = arguments.first, arguments.count == 1 else {
    print("Scripta per Windows")
    print("")
    print(usage)
    exit(arguments.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
}

if path == "-h" || path == "--help" {
    print(usage)
    exit(EXIT_SUCCESS)
}

let url = URL(fileURLWithPath: path)
let text: String
do {
    text = try String(contentsOf: url, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("ScriptaWin: impossibile leggere '\(path)': \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}

let mode = DocumentMode.inferred(fromExtension: url.pathExtension, text: text)
let stats = DocumentStatistics(text: text, mode: mode)

print("Scripta — \(url.lastPathComponent)")
if let title = stats.title, !title.isEmpty { print(title) }
print("Modalità:  \(mode.displayName)")
print("Parole:    \(stats.words)")
print("Caratteri: \(stats.characterCount)")
if mode == .screenplay {
    print("Scene:     \(stats.scenes)")
} else {
    print("Titoli:    \(stats.headings)")
}
