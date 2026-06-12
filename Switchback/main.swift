import AppKit

// Switchback runs as a menu-bar agent: no Dock icon, no app-switcher entry.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
