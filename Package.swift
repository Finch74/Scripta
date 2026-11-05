// swift-tools-version: 6.0
import PackageDescription

// ScriptaCore and the `scripta` CLI build everywhere; the GUI app needs AppKit/SwiftUI and is macOS-only.
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
#endif

let package = Package(
    name: "Scripta",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
