import Foundation
import ScriptaCore

/// `scripta`: prints the statistics and the outline of a Fountain or Markdown file.

let usage = """
    Uso: scripta [--mode screenplay|prose] <file>

    Legge un file Fountain (.fountain) o Markdown (.md) e stampa statistiche e outline.

    Opzioni:
      --mode screenplay|prose   Forza la modalità invece di dedurla dall'estensione.
      -h, --help                Mostra questo messaggio.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("scripta: \(message)\n\n\(usage)\n".utf8))
    exit(EXIT_FAILURE)
}

// MARK: - Arguments

var path: String?
var forcedMode: DocumentMode?
var arguments = CommandLine.arguments.dropFirst()

while let argument = arguments.popFirst() {
    switch argument {
    case "-h", "--help":
        print(usage)
        exit(EXIT_SUCCESS)
    case "--mode":
        guard let value = arguments.popFirst(), let mode = DocumentMode(rawValue: value) else {
            fail("--mode richiede 'screenplay' o 'prose'")
        }
        forcedMode = mode
    default:
        guard !argument.hasPrefix("-") else { fail("opzione sconosciuta '\(argument)'") }
        guard path == nil else { fail("specificare un solo file") }
        path = argument
    }
}

guard let path else { fail("nessun file specificato") }

let url = URL(fileURLWithPath: path)
let text: String
do {
    text = try String(contentsOf: url, encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("scripta: impossibile leggere '\(path)': \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}

let mode = forcedMode ?? DocumentMode.inferred(fromExtension: url.pathExtension, text: text)

// MARK: - Analysis

let stats = DocumentStatistics(text: text, mode: mode)

// MARK: - Output

func row(_ label: String, _ value: Any) {
    print("  " + label.padding(toLength: 22, withPad: " ", startingAt: 0) + "\(value)")
}

print("Scripta — \(url.lastPathComponent)")
if let title = stats.title, !title.isEmpty { print(title) }
print("")
print("STATISTICHE")
row("Modalità", mode.displayName)
row("Parole", stats.words)
row("Caratteri", stats.characterCount)
row("Righe non vuote", stats.nonEmptyLines)
if mode == .screenplay {
    row("Scene", stats.scenes)
    if stats.sections > 0 { row("Sezioni", stats.sections) }
} else {
    row("Titoli", stats.headings)
    row("Tempo di lettura", "~\(stats.readingMinutes) min")
}
if stats.pages > 0 || stats.panels > 0 {
    row("Tavole", stats.pages)
    row("Vignette", stats.panels)
}
if !stats.cast.isEmpty {
    row("Personaggi", stats.cast.count)
    row("Battute", stats.speeches)
    row("Righe di dialogo", stats.dialogueLines)
}

if !stats.cast.isEmpty {
    print("")
    print("PERSONAGGI")
    let width = min(stats.cast.map(\.name.count).max() ?? 0, 30)
    for stat in stats.cast {
        let share = stats.share(of: stat)
        print("  " + stat.name.padding(toLength: width, withPad: " ", startingAt: 0)
              + "  \(stat.speeches) battute, \(stat.words) parole (\(String(format: "%.1f", share))%)")
    }
}

print("")
print("OUTLINE")
if stats.outline.isEmpty {
    print("  (nessuna scena o titolo)")
}
for item in stats.outline {
    let indent = String(repeating: "  ", count: item.level + 1)
    let label = switch item.kind {
    case .scene(let number): "\(number). \(item.title)"
    case .section: "§ \(item.title)"
    case .heading: item.title
    case .page: "▣ \(item.title)"
    case .panel: "▢ \(item.title)"
    }
    print(indent + label)
}
