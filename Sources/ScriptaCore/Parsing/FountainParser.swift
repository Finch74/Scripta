import Foundation

/// Line-based parser for the Fountain screenplay format (https://fountain.io/syntax).
public enum FountainParser {
    public static let titlePageKeys: Set<String> = [
        "title", "credit", "author", "authors", "source", "draft date", "date",
        "contact", "copyright", "notes", "revision", "episode", "series"
    ]

    public static let boneyardRegex = try! NSRegularExpression(pattern: #"/\*[\s\S]*?(?:\*/|\z)"#)
    public static let noteRegex = try! NSRegularExpression(pattern: #"\[\[[\s\S]*?\]\]"#)
    private static let titleKeyRegex = try! NSRegularExpression(pattern: #"^\s*([A-Za-z][A-Za-z ]*):"#)
    private static let sceneRegex = try! NSRegularExpression(
        pattern: #"^(INT\.?/EXT|EXT\.?/INT|INT|EXT|EST|I/E|I\./E)[\. ]"#, options: [.caseInsensitive])
    private static let sceneNumberRegex = try! NSRegularExpression(pattern: #"\s*#([^#\n]+)#\s*$"#)

    public static func parse(_ ns: NSString) -> [ScriptLine] {
        let raw = TextLines.split(ns)
        let boneyards = TextLines.matches(boneyardRegex, in: ns)
        let notes = TextLines.matches(noteRegex, in: ns)

        func string(_ r: NSRange) -> String { ns.substring(with: r) }
        func isBlank(_ index: Int) -> Bool {
            guard index >= 0, index < raw.count else { return true }
            return TextLines.trimmed(ns, raw[index].range).length == 0
        }

        var lines: [ScriptLine] = []
        lines.reserveCapacity(raw.count)
        var index = 0

        // Title page: only valid at the very start of the document.
        if let first = raw.first, let key = titleKey(ns, first.range), titlePageKeys.contains(key.name) {
            var currentKey = key.name
            while index < raw.count, !isBlank(index) {
                let (range, full) = raw[index]
                if let k = titleKey(ns, range) {
                    currentKey = k.name
                    let valueRange = TextLines.trimmed(ns, NSRange(location: NSMaxRange(k.marker),
                                                                   length: NSMaxRange(range) - NSMaxRange(k.marker)))
                    lines.append(ScriptLine(kind: .titleField(key: currentKey), range: range, fullRange: full,
                                            textRange: valueRange, markers: [k.marker]))
                } else {
                    lines.append(ScriptLine(kind: .titleField(key: currentKey), range: range, fullRange: full,
                                            textRange: TextLines.trimmed(ns, range)))
                }
                index += 1
            }
        }

        var inDialogue = false
        var previousBlank = true

        while index < raw.count {
            let (range, full) = raw[index]
            defer { index += 1 }
            let trimmedRange = TextLines.trimmed(ns, range)
            var line = ScriptLine(kind: .action, range: range, fullRange: full, textRange: trimmedRange)

            if boneyards.contains(where: { range.isContained(in: $0) }) {
                line.kind = .boneyard
                lines.append(line)
                continue
            }

            if trimmedRange.length == 0 {
                // Two spaces keep a dialogue block alive across an intentionally empty line.
                if inDialogue, string(range) == "  " {
                    line.kind = .dialogue
                } else {
                    line.kind = .empty
                    inDialogue = false
                    previousBlank = true
                }
                lines.append(line)
                continue
            }

            if notes.contains(where: { trimmedRange.isContained(in: $0) }) {
                line.kind = .note
                lines.append(line)
                continue
            }

            let text = string(trimmedRange)
            let start = trimmedRange.location
            let lastIndex = NSMaxRange(trimmedRange) - 1
            let wasPreviousBlank = previousBlank
            previousBlank = false

            func dropFirst(_ count: Int = 1) {
                line.markers.append(NSRange(location: start, length: count))
                line.textRange = TextLines.trimmed(ns, NSRange(location: start + count, length: trimmedRange.length - count))
            }

            if inDialogue {
                line.kind = text.hasPrefix("(") ? .parenthetical : .dialogue
                lines.append(line)
                continue
            }

            if text.count >= 3, text.allSatisfy({ $0 == "=" }) {
                line.kind = .pageBreak
                line.markers = [trimmedRange]
                line.textRange = NSRange(location: start, length: 0)
            } else if text.hasPrefix("#"), GraphicNovel.detectPage(ns, in: &line) {
                // Page marker of a graphic-novel script (printed, unlike sections).
            } else if text.hasPrefix("#") {
                let level = text.prefix(while: { $0 == "#" }).count
                line.kind = .section(level: level)
                dropFirst(level)
            } else if text.hasPrefix("="), !text.hasPrefix("==") {
                line.kind = .synopsis
                dropFirst()
            } else if text.hasPrefix("!") {
                line.kind = .action
                // Forced action preserves indentation after the marker.
                line.markers = [NSRange(location: start, length: 1)]
                line.textRange = NSRange(location: start + 1, length: trimmedRange.length - 1)
            } else if text.hasPrefix("."), GraphicNovel.detectPanel(ns, in: &line) {
                // Panel of a graphic-novel page (".Vig. 1", ".PANEL 1"), not a forced scene heading.
            } else if text.hasPrefix("**"), GraphicNovel.detectBalloon(ns, in: &line) {
                // Comic balloon: "**NOME**: testo".
            } else if text.hasPrefix("."), !text.hasPrefix("..") {
                line.kind = .sceneHeading(sceneNumber: nil)
                dropFirst()
                applySceneNumber(ns, to: &line)
            } else if wasPreviousBlank, sceneRegex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
                line.kind = .sceneHeading(sceneNumber: nil)
                applySceneNumber(ns, to: &line)
            } else if text.hasPrefix(">"), text.hasSuffix("<"), trimmedRange.length >= 2 {
                line.kind = .centered
                line.markers = [NSRange(location: start, length: 1), NSRange(location: lastIndex, length: 1)]
                line.textRange = TextLines.trimmed(ns, NSRange(location: start + 1, length: trimmedRange.length - 2))
            } else if text.hasPrefix(">") {
                line.kind = .transition
                dropFirst()
            } else if text.hasPrefix("~") {
                line.kind = .lyrics
                dropFirst()
            } else if text.hasPrefix("@") {
                inDialogue = !isBlank(index + 1)
                line.kind = .character(dual: text.hasSuffix("^"))
                dropFirst()
                stripDualMarker(ns, from: &line)
            } else if wasPreviousBlank, text == text.uppercased(), text.hasSuffix("TO:"), isBlank(index + 1) {
                line.kind = .transition
            } else if wasPreviousBlank, isCharacterCue(text), !isBlank(index + 1) {
                inDialogue = true
                line.kind = .character(dual: text.hasSuffix("^"))
                stripDualMarker(ns, from: &line)
            }

            lines.append(line)
        }
        return lines
    }

    /// Heuristic used to pick a mode for plain-text files.
    public static func looksLikeScreenplay(_ text: String) -> Bool {
        let ns = text as NSString
        if let first = TextLines.split(ns).first, let key = titleKey(ns, first.range), titlePageKeys.contains(key.name) {
            return true
        }
        let probe = try! NSRegularExpression(pattern: #"^(INT|EXT|EST|I/E)[\. ]"#, options: [.anchorsMatchLines, .caseInsensitive])
        return probe.numberOfMatches(in: text, range: NSRange(location: 0, length: min(ns.length, 20_000))) >= 1
    }

    // MARK: - Helpers

    private static func titleKey(_ ns: NSString, _ range: NSRange) -> (name: String, marker: NSRange)? {
        guard let m = titleKeyRegex.firstMatch(in: ns as String, range: range) else { return nil }
        let name = ns.substring(with: m.range(at: 1)).lowercased().trimmingCharacters(in: .whitespaces)
        return (name, m.range)
    }

    private static func isCharacterCue(_ text: String) -> Bool {
        var name = text
        if name.hasSuffix("^") { name.removeLast() }
        if let paren = name.firstIndex(of: "(") { name = String(name[..<paren]) }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.contains(where: \.isLetter) else { return false }
        return name == name.uppercased() && !name.hasSuffix(":")
    }

    private static func stripDualMarker(_ ns: NSString, from line: inout ScriptLine) {
        let r = line.textRange
        guard r.length > 0, ns.character(at: NSMaxRange(r) - 1) == UInt16(UInt8(ascii: "^")) else { return }
        line.markers.append(NSRange(location: NSMaxRange(r) - 1, length: 1))
        line.textRange = TextLines.trimmed(ns, NSRange(location: r.location, length: r.length - 1))
    }

    private static func applySceneNumber(_ ns: NSString, to line: inout ScriptLine) {
        guard let m = sceneNumberRegex.firstMatch(in: ns as String, range: line.textRange) else { return }
        let number = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        line.kind = .sceneHeading(sceneNumber: number.isEmpty ? nil : number)
        line.markers.append(m.range)
        line.textRange = NSRange(location: line.textRange.location, length: m.range.location - line.textRange.location)
    }
}
