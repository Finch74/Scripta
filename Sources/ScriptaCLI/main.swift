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

/// Same rule as the app: Fountain extensions are screenplays, Markdown extensions are prose,
/// anything else is sniffed from the content.
let mode: DocumentMode = forcedMode ?? {
    switch url.pathExtension.lowercased() {
    case "fountain", "spmd": .screenplay
    case "md", "markdown", "mdown", "mkd": .prose
    default: FountainParser.looksLikeScreenplay(text) ? .screenplay : .prose
    }
}()

// MARK: - Analysis

let ns = text as NSString
let lines = mode == .screenplay ? FountainParser.parse(ns) : MarkdownParser.parse(ns)
let outline = DocumentOutline.items(in: text, mode: mode)
let characters = CharacterAnalysis.statistics(text: text, mode: mode)

/// Words of the printable text only: comments, notes, title-page fields and code are left out.
let words = lines.reduce(0) { total, line in
    switch line.kind {
    case .empty, .boneyard, .note, .titleField, .codeFence, .code, .pageBreak, .rule: total
    default: total + TextLines.wordCount(ns, in: line.textRange)
    }
}
let nonEmptyLines = lines.filter { $0.kind != .empty }.count
let dialogueLines = lines.filter { $0.kind == .dialogue || $0.kind == .balloon }.count
let title = lines.first { $0.kind == .titleField(key: "title") }
    .map { ns.substring(with: $0.textRange).replacingOccurrences(of: "*", with: "") }

func count(_ kind: (OutlineItem.Kind) -> Bool) -> Int { outline.filter { kind($0.kind) }.count }
let scenes = count { if case .scene = $0 { true } else { false } }
let sections = count { $0 == .section }
let headings = count { $0 == .heading }
let pages = count { $0 == .page }
let panels = count { $0 == .panel }

// MARK: - Output

func row(_ label: String, _ value: Any) {
    print("  " + label.padding(toLength: 22, withPad: " ", startingAt: 0) + "\(value)")
}

print("Scripta — \(url.lastPathComponent)")
if let title, !title.isEmpty { print(title) }
print("")
print("STATISTICHE")
row("Modalità", mode.displayName)
row("Parole", words)
row("Caratteri", text.count)
row("Righe non vuote", nonEmptyLines)
if mode == .screenplay {
    row("Scene", scenes)
    if sections > 0 { row("Sezioni", sections) }
} else {
    row("Titoli", headings)
    row("Tempo di lettura", "~\(max(1, Int((Double(words) / 230).rounded()))) min")
}
if pages > 0 || panels > 0 {
    row("Tavole", pages)
    row("Vignette", panels)
}
if !characters.isEmpty {
    row("Personaggi", characters.count)
    row("Battute", characters.reduce(0) { $0 + $1.speeches })
    row("Righe di dialogo", dialogueLines)
}

if !characters.isEmpty {
    print("")
    print("PERSONAGGI")
    let width = min(characters.map(\.name.count).max() ?? 0, 30)
    for stat in characters {
        let share = words > 0 ? Double(stat.words) / Double(words) * 100 : 0
        print("  " + stat.name.padding(toLength: width, withPad: " ", startingAt: 0)
              + "  \(stat.speeches) battute, \(stat.words) parole (\(String(format: "%.1f", share))%)")
    }
}

print("")
print("OUTLINE")
if outline.isEmpty {
    print("  (nessuna scena o titolo)")
}
for item in outline {
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
