import AppKit
import SwiftUI
import ScriptaCore

enum Gender: String, CaseIterable, Identifiable, Codable, Sendable {
    case unspecified, female, male, nonBinary

    var id: Self { self }

    var displayName: String {
        switch self {
        case .unspecified: "Non specificato"
        case .female: "Femminile"
        case .male: "Maschile"
        case .nonBinary: "Non binario"
        }
    }

    /// Colour used in the gender breakdown chart.
    var chartColor: Color {
        switch self {
        case .unspecified: .gray
        case .female: .pink
        case .male: .blue
        case .nonBinary: .purple
        }
    }
}

struct CharacterProfile: Codable, Equatable, Sendable {
    var gender: Gender = .unspecified
    /// sRGB hex (`#RRGGBB`) of the highlight colour; `nil` means not highlighted.
    var highlightHex: String?
}

/// Gender and highlight colour of each character, persisted in UserDefaults per document
/// (Fountain files are plain text, so there is nowhere else to keep them).
@MainActor
final class CharacterProfileStore: ObservableObject {
    static let defaultsKey = "characterProfiles"

    /// Colours handed out, in order, when a character is first highlighted.
    static let palette = ["#F6C344", "#7FC8A9", "#F28B82", "#8AB4F8", "#C58AF9", "#FDA65D", "#78D9EC", "#E8A0BF"]

    @Published private(set) var profiles: [String: CharacterProfile] = [:]
    private var scope: String

    init(fileURL: URL?) {
        scope = Self.scope(for: fileURL)
        profiles = Self.loadAll()[scope] ?? [:]
    }

    func profile(for name: String) -> CharacterProfile {
        profiles[name] ?? CharacterProfile()
    }

    func update(_ name: String, _ modify: (inout CharacterProfile) -> Void) {
        var profile = self.profile(for: name)
        modify(&profile)
        profiles[name] = profile == CharacterProfile() ? nil : profile
        save()
    }

    func setHighlighted(_ name: String, _ on: Bool) {
        update(name) { profile in
            if !on {
                profile.highlightHex = nil
            } else if profile.highlightHex == nil {
                let used = profiles.values.compactMap(\.highlightHex).count
                profile.highlightHex = Self.palette[used % Self.palette.count]
            }
        }
    }

    /// Highlight colours keyed by character name, for the editor.
    var highlightColors: [String: NSColor] {
        profiles.compactMapValues { $0.highlightHex.flatMap(NSColor.init(hex:)) }
    }

    /// Follows the document when it is saved under a new name, carrying over the current profiles.
    func rebind(to fileURL: URL?) {
        let newScope = Self.scope(for: fileURL)
        guard newScope != scope else { return }
        scope = newScope
        let stored = Self.loadAll()[newScope] ?? [:]
        if stored.isEmpty { save() } else { profiles = stored }
    }

    // MARK: - Persistence

    private static func scope(for url: URL?) -> String {
        url?.standardizedFileURL.path ?? "untitled"
    }

    private static func loadAll() -> [String: [String: CharacterProfile]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let all = try? JSONDecoder().decode([String: [String: CharacterProfile]].self, from: data) else { return [:] }
        return all
    }

    private func save() {
        var all = Self.loadAll()
        all[scope] = profiles.isEmpty ? nil : profiles
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
