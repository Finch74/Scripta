import SwiftUI
import UniformTypeIdentifiers
import ScriptaCore

struct ScriptaDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fountain, .markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.fountain, .markdownText, .plainText] }

    var text: String
    /// Mode inferred when the file was opened; not persisted (the file extension carries it).
    var initialMode: DocumentMode

    init(text: String = "", mode: DocumentMode = .screenplay) {
        self.text = text
        self.initialMode = mode
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = Self.decode(data)
        let type = configuration.contentType
        if type.conforms(to: .fountain) {
            initialMode = .screenplay
        } else if type.conforms(to: .markdownText) {
            initialMode = .prose
        } else {
            // Other apps may own the extension (e.g. "io.fountain"): fall back to the file name, then the content.
            let ext = ((configuration.file.filename ?? "") as NSString).pathExtension
            initialMode = DocumentText.mode(forExtension: ext, text: text)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    static func decode(_ data: Data) -> String {
        DocumentText.decode(data)
    }

    static func mode(forExtension ext: String, text: String) -> DocumentMode {
        DocumentText.mode(forExtension: ext, text: text)
    }
}
