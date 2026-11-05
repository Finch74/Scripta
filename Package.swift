// swift-tools-version: 6.0
import PackageDescription

// ScriptaCore and the `scripta` CLI build everywhere. The GUI front ends are platform-specific:
// ScriptaApp needs AppKit/SwiftUI (macOS), ScriptaGTK needs GTK 4 (Linux, found via pkg-config).
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
    .executableTarget(
        name: "ScriptaGTK",
        dependencies: ["ScriptaCore", "CGtk"],
        path: "Sources/ScriptaGTK",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
])
#endif

let package = Package(
    name: "Scripta",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
