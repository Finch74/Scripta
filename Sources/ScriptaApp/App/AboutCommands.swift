import AppKit
import SwiftUI
import ScriptaCore

/// "Scripta → Informazioni su Scripta": the standard About panel with copyright, website and the
/// full MIT license (the same text as LICENSE and the GTK About dialog).
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Informazioni su Scripta") { AboutPanel.show() }
        }
    }
}

@MainActor
enum AboutPanel {
    static let copyright = "© 2026 Finch74"
    static let website = URL(string: "https://github.com/Finch74/Scripta")!

    static func show() {
        // Fallbacks for a bare executable (swift run), which has no Info.plist.
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Scripta",
            .applicationVersion: shortVersion,
            .version: build,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "\(copyright) — Licenza MIT",
            .credits: credits(),
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static func credits() -> NSAttributedString {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(
            string: "Sceneggiature (Fountain), prosa (Markdown) e script per fumetti.\n", attributes: body)
        var link = body
        link[.link] = website
        credits.append(NSAttributedString(string: website.absoluteString, attributes: link))
        credits.append(NSAttributedString(string: "\n\n", attributes: body))
        credits.append(NSAttributedString(string: licenseText, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return credits
    }
}
