import AppKit
import ScriptaCore

/// Fonts, colours and paragraph metrics used by the on-screen editor.
///
/// Screenplay metrics follow the industry layout expressed in character columns
/// (10 columns = 1 inch for 12pt Courier), so the editor mirrors the printed page.
struct EditorStyle {
    struct Element {
        let font: NSFont
        let color: NSColor
        let paragraph: NSParagraphStyle
    }

    let mode: DocumentMode
    let baseFont: NSFont
    let columnWidth: CGFloat

    // Dynamic colours: each resolves against the drawing view's effective appearance, so a theme
    // change restyles the text storage without re-highlighting.
    static let textColor = dynamic(light: .black, dark: rgb(0xE6, 0xE4, 0xDF))
    static let backgroundColor = dynamic(light: .white, dark: rgb(0x1E, 0x1F, 0x22))
    static let markerColor = dynamic(light: NSColor(calibratedWhite: 0.68, alpha: 1), dark: NSColor(calibratedWhite: 0.44, alpha: 1))
    static let boneyardColor = dynamic(light: NSColor(calibratedWhite: 0.6, alpha: 1), dark: NSColor(calibratedWhite: 0.5, alpha: 1))
    static let notesColor = dynamic(light: rgb(0x49, 0x9C, 0x91), dark: rgb(0x6F, 0xC6, 0xB9))
    static let sectionColor = dynamic(light: rgb(0x06, 0x45, 0x5F), dark: rgb(0x7F, 0xB8, 0xD6))
    static let insertionPointColor = dynamic(light: .black, dark: rgb(0xFF, 0xC8, 0x57))
    static let selectionColor = dynamic(light: NSColor(calibratedRed: 0.80, green: 0.88, blue: 1, alpha: 1),
                                        dark: rgb(0x2F, 0x4A, 0x70))

    /// Colour of inactive text in focus mode.
    static let focusDimColor = dynamic(light: NSColor(calibratedWhite: 0.78, alpha: 1), dark: NSColor(calibratedWhite: 0.36, alpha: 1))

    static var selectedTextAttributes: [NSAttributedString.Key: Any] {
        [.backgroundColor: selectionColor]
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private let charWidth: CGFloat
    private var cache: [String: Element] = [:]

    init(mode: DocumentMode, scale: CGFloat = 1) {
        self.mode = mode
        switch mode {
        case .screenplay:
            let size = 14 * scale
            baseFont = Self.font(["CourierPrime", "Courier Prime", "CourierNewPSMT", "Courier"], size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
            charWidth = ("M" as NSString).size(withAttributes: [.font: baseFont]).width
            columnWidth = ceil(charWidth * 61)
        case .prose:
            let size = 18 * scale
            baseFont = Self.font(["IowanOldStyle-Roman", "Charter-Roman", "Georgia"], size: size)
                ?? .systemFont(ofSize: size)
            charWidth = ("n" as NSString).size(withAttributes: [.font: baseFont]).width
            columnWidth = 680 * scale
        }
        cache = buildElements()
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        let element = self.element(for: mode == .screenplay ? .action : .paragraph)
        return [.font: element.font, .foregroundColor: Self.textColor, .paragraphStyle: element.paragraph]
    }

    func element(for kind: LineKind) -> Element {
        cache[Self.key(for: kind)] ?? cache["base"]!
    }

    // MARK: - Construction

    private static func key(for kind: LineKind) -> String {
        switch kind {
        case .heading(let level): "h\(min(level, 4))"
        case .section(let level): "section\(min(level, 3))"
        case .bullet(let indent), .ordered(let indent, _): "list\(min(indent, 6))"
        case .sceneHeading: "scene"
        case .character: "character"
        case .titleField: "title"
        default: "\(kind)"
        }
    }

    private func buildElements() -> [String: Element] {
        var out: [String: Element] = [:]
        let fm = NSFontManager.shared
        let bold = fm.convert(baseFont, toHaveTrait: .boldFontMask)
        let italic = fm.convert(baseFont, toHaveTrait: .italicFontMask)
        let black = Self.textColor // dynamic: black in light mode, off-white in dark mode

        func paragraph(_ configure: (NSMutableParagraphStyle) -> Void = { _ in }) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = mode == .screenplay ? 1.12 : 1.5
            configure(p)
            return p.copy() as! NSParagraphStyle
        }
        func indent(_ head: CGFloat, width: CGFloat? = nil) -> NSParagraphStyle {
            paragraph { p in
                p.firstLineHeadIndent = head * charWidth
                p.headIndent = head * charWidth
                if let width { p.tailIndent = (head + width) * charWidth }
            }
        }

        out["base"] = Element(font: baseFont, color: black, paragraph: paragraph())
        out["graphicNovelPage"] = Element(font: fm.convert(bold, toSize: baseFont.pointSize * 1.25), color: black,
                                          paragraph: paragraph { $0.paragraphSpacingBefore = baseFont.pointSize * 0.5 })
        out["panel"] = Element(font: bold, color: black, paragraph: paragraph())
        out["balloon"] = Element(font: baseFont, color: black, paragraph: paragraph())

        switch mode {
        case .screenplay:
            out["action"] = Element(font: baseFont, color: black, paragraph: paragraph())
            out["empty"] = out["action"]
            out["scene"] = Element(font: bold, color: black, paragraph: paragraph())
            out["character"] = Element(font: baseFont, color: black, paragraph: indent(22))
            out["dialogue"] = Element(font: baseFont, color: black, paragraph: indent(10, width: 35))
            out["parenthetical"] = Element(font: baseFont, color: black, paragraph: indent(16, width: 22))
            out["transition"] = Element(font: baseFont, color: black, paragraph: paragraph { $0.alignment = .right })
            out["centered"] = Element(font: baseFont, color: black, paragraph: paragraph { $0.alignment = .center })
            out["lyrics"] = Element(font: italic, color: black, paragraph: indent(10, width: 40))
            out["pageBreak"] = Element(font: baseFont, color: Self.markerColor, paragraph: paragraph())
            out["synopsis"] = Element(font: italic, color: Self.markerColor, paragraph: paragraph())
            out["note"] = Element(font: baseFont, color: Self.notesColor, paragraph: paragraph())
            out["boneyard"] = Element(font: baseFont, color: Self.boneyardColor, paragraph: paragraph())
            out["title"] = Element(font: baseFont, color: black, paragraph: paragraph())
            for level in 1...3 {
                out["section\(level)"] = Element(font: bold, color: Self.sectionColor, paragraph: paragraph())
            }
            // Dialogue continuation through Markdown kinds is never produced in screenplay mode.
        case .prose:
            let size = baseFont.pointSize
            let mono = NSFont.monospacedSystemFont(ofSize: size * 0.82, weight: .regular)
            out["paragraph"] = Element(font: baseFont, color: black, paragraph: paragraph())
            out["empty"] = out["paragraph"]
            let headingScales: [CGFloat] = [1.6, 1.35, 1.18, 1.05]
            for (i, scale) in headingScales.enumerated() {
                let font = fm.convert(fm.convert(baseFont, toSize: size * scale), toHaveTrait: .boldFontMask)
                out["h\(i + 1)"] = Element(font: font, color: black, paragraph: paragraph { p in
                    p.lineHeightMultiple = 1.25
                    p.paragraphSpacingBefore = size * 0.4
                })
            }
            out["blockquote"] = Element(font: italic, color: black, paragraph: paragraph { p in
                p.firstLineHeadIndent = 28
                p.headIndent = 28
                p.tailIndent = -28
            })
            for level in 0...6 {
                let base = CGFloat(level) * 28
                out["list\(level)"] = Element(font: baseFont, color: black, paragraph: paragraph { p in
                    p.firstLineHeadIndent = base
                    p.headIndent = base + charWidth * 2.6
                })
            }
            out["code"] = Element(font: mono, color: black, paragraph: paragraph { p in
                p.lineHeightMultiple = 1.2
                p.firstLineHeadIndent = 20
                p.headIndent = 20
            })
            out["codeFence"] = Element(font: mono, color: Self.markerColor, paragraph: out["code"]!.paragraph)
            out["rule"] = Element(font: baseFont, color: Self.markerColor, paragraph: paragraph { $0.alignment = .center })
            out["pageBreak"] = out["rule"]
            out["boneyard"] = Element(font: baseFont, color: Self.boneyardColor, paragraph: paragraph())
        }
        return out
    }

    private static func font(_ names: [String], size: CGFloat) -> NSFont? {
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return nil
    }
}
