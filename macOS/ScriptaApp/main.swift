import AppKit
import ScriptaCore

if CommandLine.arguments.contains("--export") {
    CommandLineExport.run(CommandLine.arguments)
} else if CommandLine.arguments.contains("--snapshot") {
    EditorSnapshot.run(CommandLine.arguments)
} else {
    // Ensures a menu bar and key focus even when launched as a bare executable (swift run).
    NSApplication.shared.setActivationPolicy(.regular)
    ScriptaApp.main()
}
