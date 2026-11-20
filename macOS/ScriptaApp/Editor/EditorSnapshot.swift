import AppKit
import ScriptaCore

/// Headless rendering of the live editor, used to verify formatting without a visible window:
/// `Scripta --snapshot <input> <output.png> [--type "text to append"] [--dark] [--focus] [--highlight NAME]`
///
/// The optional `--type` text is inserted character by character through `insertText`, exercising
/// the same incremental highlighting path used while the user types.
@MainActor
enum EditorSnapshot {
    static func run(_ arguments: [String]) -> Never {
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 2 else {
            FileHandle.standardError.write(Data("Uso: Scripta --snapshot <input> <output.png> [--type testo] [--dark] [--focus] [--highlight NOME]\n".utf8))
            exit(1)
        }
        let input = URL(fileURLWithPath: arguments[flag + 1])
        let output = URL(fileURLWithPath: arguments[flag + 2])
        let text = (try? Data(contentsOf: input)).map(ScriptaDocument.decode) ?? ""
        let mode = ScriptaDocument.mode(forExtension: input.pathExtension, text: text)

        let (scrollView, textView) = ScriptEditor.makeTextSystem()
        // Headless: pin the appearance so output is deterministic (`--dark` renders the dark theme).
        scrollView.appearance = (arguments.contains("--dark") ? AppTheme.dark : .light).appearance
        textView.applyThemeColors()
        let storage = textView.textStorage!
        let highlighter = SyntaxHighlighter(mode: mode)
        highlighter.textView = textView
        storage.delegate = highlighter
        textView.columnWidth = highlighter.style.columnWidth
        textView.typingAttributes = highlighter.style.baseAttributes
        textView.string = text
        highlighter.rehighlight(storage)

        if let i = arguments.firstIndex(of: "--type"), arguments.count > i + 1 {
            textView.setSelectedRange(NSRange(location: storage.length, length: 0))
            for character in arguments[i + 1].replacingOccurrences(of: "\\n", with: "\n") {
                textView.insertText(String(character), replacementRange: textView.selectedRange())
            }
        }

        // `--highlight NAME` tints that character's speeches and prints the per-character statistics.
        if let i = arguments.firstIndex(of: "--highlight"), arguments.count > i + 1 {
            textView.documentMode = mode
            textView.characterHighlights = [CharacterAnalysis.normalizedName(arguments[i + 1]):
                                                NSColor(hex: CharacterProfileStore.palette[0])!]
            for stat in CharacterAnalysis.statistics(text: textView.string, mode: mode) {
                print("\(stat.name): \(stat.speeches) battute, \(stat.words) parole")
            }
        }
        // `--focus` dims everything but the paragraph holding the caret.
        textView.focusMode = arguments.contains("--focus")

        let width: CGFloat = 900
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()
        let bounds = NSRect(x: 0, y: 0, width: width, height: min(textView.frame.height, 4000))
        textView.frame.size.height = bounds.height

        guard let rep = textView.bitmapImageRepForCachingDisplay(in: bounds) else { exit(1) }
        textView.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: output)) != nil else { exit(1) }
        print("Snapshot: \(output.path)")
        exit(0)
    }
}
