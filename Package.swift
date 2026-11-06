// swift-tools-version: 6.0
import PackageDescription

// ScriptaCore and the `scripta` CLI build everywhere. The GUI front ends are platform-specific:
// ScriptaApp needs AppKit/SwiftUI (macOS), ScriptaGTK needs GTK 4 (Linux, found via pkg-config),
// ScriptaWin (Windows) depends on ScriptaCore only. The CGtk/CWebKit/CPoppler system libraries are
// declared only inside the Linux branch, so they are never resolved on macOS or Windows.
var products: [Product] = [
    .library(name: "ScriptaCore", targets: ["ScriptaCore"]),
    .executable(name: "scripta", targets: ["ScriptaCLI"]),
]

var targets: [Target] = [
    .target(
        name: "ScriptaCore",
        path: "Sources/ScriptaCore",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
        name: "ScriptaCLI",
        dependencies: ["ScriptaCore"],
        path: "Sources/ScriptaCLI",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
]

#if os(macOS)
products.append(.executable(name: "ScriptaApp", targets: ["ScriptaApp"]))
targets.append(
    .executableTarget(
        name: "ScriptaApp",
        dependencies: ["ScriptaCore"],
        path: "Sources/ScriptaApp",
        swiftSettings: [.swiftLanguageMode(.v6)]
    )
)
#elseif os(Linux)
products.append(.executable(name: "scripta-gtk", targets: ["ScriptaGTK"]))
targets.append(contentsOf: [
    .systemLibrary(
        name: "CGtk",
        path: "Sources/CGtk",
        pkgConfig: "gtk4",
        providers: [.apt(["libgtk-4-dev"]), .yum(["gtk4-devel"])]
    ),
    // PDF export: WebKitGTK paginates the HTML, Poppler + cairo add page numbers and metadata.
    .systemLibrary(
        name: "CWebKit",
        path: "Sources/CWebKit",
        pkgConfig: "webkitgtk-6.0",
        providers: [.apt(["libwebkitgtk-6.0-dev"]), .yum(["webkitgtk6.0-devel"])]
    ),
    // No `pkgConfig:` here: SwiftPM cannot parse the multi-line `Requires.private` of poppler-glib.pc.
    // The header is included by its standard path and the library is linked from the module map;
    // GLib and cairo flags already come from gtk4.
    .systemLibrary(
        name: "CPoppler",
        path: "Sources/CPoppler",
        providers: [.apt(["libpoppler-glib-dev"]), .yum(["poppler-glib-devel"])]
    ),
    .executableTarget(
        name: "ScriptaGTK",
        dependencies: ["ScriptaCore", "CGtk", "CWebKit", "CPoppler"],
        path: "Sources/ScriptaGTK",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
])
#elseif os(Windows)
// Windows front end: ScriptaCore only, no system libraries (GTK, WebKit and Poppler are Linux-only).
products.append(.executable(name: "ScriptaWin", targets: ["ScriptaWin"]))
targets.append(
    .executableTarget(
        name: "ScriptaWin",
        dependencies: ["ScriptaCore"],
        path: "Sources/ScriptaWin",
        swiftSettings: [.swiftLanguageMode(.v6)]
    )
)
#endif

let package = Package(
    name: "Scripta",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
