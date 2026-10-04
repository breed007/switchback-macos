import AppKit

#if DEBUG
// Debug-only Terminal hooks for the privileged helper (see DebugCommands).
if let code = DebugCommands.run(CommandLine.arguments) { exit(code) }
#endif

// Switchback runs as a menu-bar agent: no Dock icon, no app-switcher entry.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
