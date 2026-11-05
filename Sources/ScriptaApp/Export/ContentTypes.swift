import Foundation
import UniformTypeIdentifiers
#if canImport(ScriptaCore)
import ScriptaCore
#endif

// Foundation-only helpers shared by the app and the Quick Look extension (built from the same sources).

extension UTType {
    /// Declared (exported) by Scripta in Info.plist.
    static let fountain = UTType(exportedAs: "com.scripta.fountain", conformingTo: .plainText)
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

enum DocumentText {
    /// Decodes text files written by any reasonable editor (UTF-8 with or without BOM, UTF-16, legacy encodings).
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) {
            return s
        }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    static func mode(forExtension ext: String, text: String) -> DocumentMode {
        switch ext.lowercased() {
        case "fountain", "spmd": .screenplay
        case "md", "markdown": .prose
        default: FountainParser.looksLikeScreenplay(text) ? .screenplay : .prose
        }
    }
}
