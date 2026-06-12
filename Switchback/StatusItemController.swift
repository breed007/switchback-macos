import AppKit

/// Owns the menu-bar status item and builds the location menu.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor = StatusMonitor()
    private let switcher: LocationSwitcher = AuthorizedSwitcher()

    init() {
        if let button = statusItem.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true   // recolor for light/dark menu bars
            icon?.size = NSSize(width: 18, height: 18)
            icon?.accessibilityDescription = "Switchback"
            button.image = icon
        }
        monitor.onChange = { [weak self] in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if monitor.locations.isEmpty {
            menu.addItem(disabled("No network locations found"))
        } else if monitor.locations.count == 1 {
            // A single "Automatic" location is the common default; show it, then
            // make creating a second one the obvious next step.
            let only = monitor.locations[0]
            let currentItem = NSMenuItem(title: only.name, action: nil, keyEquivalent: "")
            currentItem.state = .on
            menu.addItem(currentItem)
            menu.addItem(item(title: "New Location…", action: #selector(newLocation)))
        } else {
            for loc in monitor.locations {
                let mi = item(title: loc.name, action: #selector(selectLocation(_:)))
                mi.representedObject = loc.id
                mi.state = loc.isCurrent ? .on : .off
                menu.addItem(mi)
            }
            menu.addItem(.separator())
            menu.addItem(item(title: "New Location…", action: #selector(newLocation)))
            menu.addItem(manageMenuItem())
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "Network Settings…", action: #selector(openNetworkSettings)))
        menu.addItem(item(title: "Quit Switchback", action: #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    /// The "Manage Locations" submenu: rename any editable location, delete any
    /// that isn't current or protected. Omitted entirely when nothing is editable.
    private func manageMenuItem() -> NSMenuItem {
        let editable = monitor.locations.filter { !$0.isProtected }
        let deletable = editable.filter { !$0.isCurrent }

        let submenu = NSMenu()

        let renameHeader = disabled("Rename")
        submenu.addItem(renameHeader)
        for loc in editable {
            let mi = item(title: "  \(loc.name)…", action: #selector(renameLocation(_:)))
            mi.representedObject = loc.id
            submenu.addItem(mi)
        }

        submenu.addItem(.separator())
        let deleteHeader = disabled("Delete")
        submenu.addItem(deleteHeader)
        if deletable.isEmpty {
            submenu.addItem(disabled("  (switch away to delete)"))
        } else {
            for loc in deletable {
                let mi = item(title: "  \(loc.name)", action: #selector(deleteLocation(_:)))
                mi.representedObject = loc.id
                submenu.addItem(mi)
            }
        }

        let parent = NSMenuItem(title: "Manage Locations", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        // Nothing editable (e.g. only "Automatic" plus the current set): no submenu.
        parent.isEnabled = !editable.isEmpty
        return parent
    }

    // MARK: - Actions

    @objc private func selectLocation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        perform { try switcher.switchTo(locationID: id) }
    }

    @objc private func newLocation() {
        guard let name = promptForName(title: "New Location",
                                       message: "Name for the new network location:",
                                       defaultValue: "") else { return }
        perform { try switcher.createLocation(named: name) }
    }

    @objc private func renameLocation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let loc = monitor.locations.first(where: { $0.id == id }) else { return }
        guard let name = promptForName(title: "Rename Location",
                                       message: "New name for \u{201C}\(loc.name)\u{201D}:",
                                       defaultValue: loc.name) else { return }
        perform { try switcher.renameLocation(locationID: id, to: name) }
    }

    @objc private func deleteLocation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let loc = monitor.locations.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let confirm = NSAlert()
        confirm.messageText = "Delete \u{201C}\(loc.name)\u{201D}?"
        confirm.informativeText = "This removes the location and its saved network settings. This can\u{2019}t be undone."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        perform { try switcher.deleteLocation(locationID: id) }
    }

    @objc private func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Helpers

    /// Run a privileged operation, then refresh. Auth cancellation surfaces as a
    /// thrown error from the backend; we treat a user cancel as a no-op, not a failure.
    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            monitor.reload()
            rebuildMenu()
        } catch {
            presentError(error)
        }
    }

    /// Modal text prompt. Returns the entered string, or nil if the user cancelled.
    private func promptForName(title: String, message: String, defaultValue: String) -> String? {
        // A menu-bar agent isn't active by default; without this the modal can
        // appear unfocused or behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage   // show the branded Switchback mark
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = "Location name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func item(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn\u{2019}t complete that change"
        alert.informativeText = "\(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
