import AppIntents
import AppKit
import ServiceManagement

/// Owns the menu-bar status item: builds the location menu, opens the Manage
/// Locations window, and runs every change through `switcher`.
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let showNameKey = "ShowLocationNameInMenuBar"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor = StatusMonitor()
    private let switcher: LocationSwitcher = SwitchRouter.shared
    private let order = LocationOrder()
    private let menu = NSMenu()
    private var isBusy = false
    private var manageWindow: ManageLocationsWindowController?
    /// The current location last seen, so a switch from any source can be noticed.
    private var lastCurrentID: String?
    /// Pending reset of the name flashed next to the icon; nil when not flashing.
    private var flashReset: DispatchWorkItem?
    /// The location IDs and names last given to Siri and Spotlight.
    private var publishedLocations: [String] = []

    override init() {
        super.init()
        if let button = statusItem.button {
            let icon = NSImage(named: "MenuBarIcon")
            icon?.isTemplate = true   // recolor for light/dark menu bars
            icon?.size = NSSize(width: 18, height: 18)
            icon?.accessibilityDescription = "Switchback"
            button.image = icon
        }
        menu.delegate = self
        statusItem.menu = menu
        // Live updates (a switch made elsewhere, a DHCP change for the details line).
        monitor.onChange = { [weak self] in
            DispatchQueue.main.async { self?.locationsChanged(announce: true) }
        }
        // Shortcuts or a Focus switched: refresh and flash, even if the dynamic store
        // didn't notice (two locations with the same IPv4 setup).
        NotificationCenter.default.addObserver(forName: .switchbackLocationChanged, object: nil, queue: .main) { [weak self] _ in
            self?.monitor.reload()
            self?.locationsChanged(announce: true)
        }
        locationsChanged(announce: false)
    }

    /// Re-read live state each time the menu opens. The event subscription can miss
    /// an external switch (the current-set pointer isn't an `SCDynamicStore` key), so
    /// this is the reliable read.
    func menuWillOpen(_ menu: NSMenu) {
        monitor.reload()
        locationsChanged(announce: false, refreshWindow: false)
    }

    /// Locations in the user's order (F5).
    private var locations: [NetworkLocation] {
        var ids = order.ids
        #if DEBUG
        if DemoData.active { ids = DemoData.order }
        #endif
        return LocationOrder.apply(ids, to: monitor.locations)
    }

    /// Update everything that shows locations. With `announce`, a change of the
    /// current location flashes its name next to the icon (F6).
    private func locationsChanged(announce: Bool, refreshWindow: Bool = true) {
        rebuildMenu()
        if refreshWindow { manageWindow?.refresh() }
        let current = monitor.locations.first(where: \.isCurrent)
        if announce, let current, let last = lastCurrentID, current.id != last {
            flash(current.name)
        }
        lastCurrentID = current?.id
        if flashReset == nil { updateTitle() }

        // Siri and Spotlight phrases name locations; refresh them when the list changes.
        let published = monitor.locations.map { "\($0.id)\t\($0.name)" }
        if published != publishedLocations {
            publishedLocations = published
            SwitchbackShortcuts.updateAppShortcutParameters()
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()

        let list = locations
        if list.isEmpty {
            menu.addItem(disabled("No network locations found"))
        }
        for (index, location) in list.enumerated() {
            // ⌘1 to ⌘9 for the first nine, in the user's order (F8).
            let mi = item(title: location.name, action: #selector(selectLocation(_:)),
                          key: index < 9 ? String(index + 1) : "")
            mi.representedObject = location.id
            mi.state = location.isCurrent ? .on : .off
            menu.addItem(mi)
            if location.isCurrent { menu.addItem(detailsItem()) }
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "New Location…", action: #selector(newLocationFromMenu)))
        menu.addItem(item(title: "Manage Locations…", action: #selector(showManageWindow)))

        menu.addItem(.separator())
        menu.addItem(item(title: "Network Settings…", action: #selector(openNetworkSettings)))
        switch HelperClient.status {
        case .enabled:
            break
        case .requiresApproval:
            menu.addItem(item(title: "Approve Passwordless Switching…", action: #selector(setUpHelper)))
        default:
            menu.addItem(item(title: "Set Up Passwordless Switching…", action: #selector(setUpHelper)))
        }
        let showNameItem = item(title: "Show Location Name in Menu Bar", action: #selector(toggleShowName))
        showNameItem.state = showName ? .on : .off
        menu.addItem(showNameItem)
        let login = item(title: LoginItem.requiresApproval ? "Launch at Login (Needs Approval)" : "Launch at Login",
                         action: #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isEnabled ? .on : (LoginItem.requiresApproval ? .mixed : .off)
        menu.addItem(login)
        menu.addItem(item(title: "Quit Switchback", action: #selector(quit), key: "q"))
    }

    /// The live details line under the current location (F6).
    private func detailsItem() -> NSMenuItem {
        let mi = NSMenuItem()
        mi.attributedTitle = NSAttributedString(string: NetworkDetails.current().summary, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        mi.indentationLevel = 1
        mi.isEnabled = false
        return mi
    }

    // MARK: - Menu-bar title (F6)

    private var showName: Bool { UserDefaults.standard.bool(forKey: Self.showNameKey) }

    /// Show `text` (or the current location's name, if that option is on) next to
    /// the icon, or the icon alone.
    private func updateTitle(_ text: String? = nil) {
        guard let button = statusItem.button else { return }
        let name = text ?? (showName ? monitor.locations.first(where: \.isCurrent)?.name : nil)
        button.title = name.map { " \($0)" } ?? ""
        button.imagePosition = name == nil ? .imageOnly : .imageLeading
    }

    /// Show the new location's name for about three seconds after a switch.
    private func flash(_ name: String) {
        flashReset?.cancel()
        updateTitle(name)
        let reset = DispatchWorkItem { [weak self] in
            self?.flashReset = nil
            self?.updateTitle()
        }
        flashReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: reset)
    }

    @objc private func toggleShowName() {
        UserDefaults.standard.set(!showName, forKey: Self.showNameKey)
        if flashReset == nil { updateTitle() }
    }

    // MARK: - Location actions

    @objc private func selectLocation(_ sender: NSMenuItem) {
        // Choosing the location you're already on does nothing. Without the helper,
        // "switching" to it would ask for a password for no change.
        guard let id = sender.representedObject as? String,
              monitor.locations.first(where: { $0.id == id })?.isCurrent == false else { return }
        perform { try await self.switcher.switchTo(locationID: id) }
    }

    @objc private func newLocationFromMenu() {
        newLocation()
    }

    /// Ask for a name (checked as you type, F4), then create the location. If the
    /// backend still rejects the name, reopen the dialog with the typed text.
    private func newLocation(initial: String = "", error: String? = nil) {
        monitor.reload()
        let dialog = NameDialog(title: "New Location", message: "Name for the new network location:",
                                initial: initial, existing: existingNames(), error: error)
        guard let name = dialog.run() else { return }
        perform({ try await self.switcher.createLocation(named: name) },
                onNameError: { [weak self] problem in self?.newLocation(initial: name, error: problem.description) })
    }

    private func rename(id: String, to name: String) {
        perform { try await self.switcher.renameLocation(locationID: id, to: name) }
    }

    private func delete(id: String) {
        perform { try await self.switcher.deleteLocation(locationID: id) }
    }

    @objc private func showManageWindow() {
        if manageWindow == nil {
            manageWindow = ManageLocationsWindowController(actions: .init(
                locations: { [weak self] in self?.locations ?? [] },
                create: { [weak self] in self?.newLocation() },
                rename: { [weak self] id, name in self?.rename(id: id, to: name) },
                delete: { [weak self] id in self?.delete(id: id) },
                reorder: { [weak self] ids in
                    self?.order.save(ids)
                    self?.rebuildMenu()
                }))
        }
        manageWindow?.show()
    }

    private func existingNames() -> [LocationNameValidator.Existing] {
        monitor.locations.map { LocationNameValidator.Existing(id: $0.id, name: $0.name) }
    }

    // MARK: - Settings actions

    /// Register the privileged helper, then send the user to approve it. The item
    /// disappears from the menu once the helper is enabled.
    @objc private func setUpHelper() {
        if HelperClient.status == .requiresApproval {
            HelperClient.openApprovalSettings()
            return
        }
        do {
            try HelperClient.register()
        } catch {
            presentError(error)
            return
        }
        guard HelperClient.status == .requiresApproval else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Approve Switchback\u{2019}s helper"
        alert.informativeText = "To switch locations without a password, turn on Switchback under Login Items & Extensions in System Settings. This needs an administrator, once."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            HelperClient.openApprovalSettings()
        }
    }

    /// Launch at Login on/off. If macOS wants approval first, send the user to the
    /// Login Items settings instead of failing silently.
    @objc private func toggleLaunchAtLogin() {
        if LoginItem.requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            presentError(error)
        }
        if LoginItem.requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Helpers

    /// Run a privileged operation, then refresh the menu and window. The work is
    /// async (the helper replies over XPC; the admin-prompt backend runs on its own
    /// queue), so the menu bar never blocks. Canceling the auth panel is a silent
    /// no-op. A name problem goes to `onNameError` (to reopen the dialog), after
    /// the busy flag clears so the retry isn't ignored. Re-entrant calls while one
    /// is in flight are ignored.
    private func perform(_ work: @escaping () async throws -> Void,
                         onNameError: ((LocationSwitcherError) -> Void)? = nil) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            var failure: Error?
            do { try await work() } catch { failure = error }
            isBusy = false
            monitor.reload()
            locationsChanged(announce: true)

            guard let failure else { return }
            if let problem = failure as? LocationSwitcherError {
                if case .canceled = problem { return }
                if problem.isNameProblem, let onNameError {
                    onNameError(problem)
                    return
                }
            }
            presentError(failure)
        }
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

#if DEBUG
extension StatusItemController {
    private static var demoBackdrop: NSWindow?

    /// The real menu as it would open, one line per item (debug flag `--menu`).
    func debugMenuDump() -> [String] {
        menuWillOpen(menu)
        let title = statusItem.button?.title ?? ""
        return ["menu-bar title: \(title.isEmpty ? "(icon only)" : "\"\(title)\"")"] + menu.items.map { mi in
            if mi.isSeparatorItem { return "  ────────" }
            let state = mi.state == .on ? "✓ " : (mi.state == .mixed ? "– " : "  ")
            let indent = String(repeating: "    ", count: mi.indentationLevel)
            let key = mi.keyEquivalent.isEmpty ? "" : "   ⌘\(mi.keyEquivalent.uppercased())"
            return "\(state)\(indent)\(mi.attributedTitle?.string ?? mi.title)\(key)\(mi.isEnabled ? "" : "   (disabled)")"
        }
    }

    /// Open one piece of UI with sample data for a screenshot (debug flag `--demo`).
    func debugDemo(_ what: String) {
        menu.appearance = NSApp.appearance
        // A backdrop in GitHub's page color, above everything else on screen and
        // just below menus. The script captures the composited screen region, so
        // menu and window materials blend with this (as they would with a desktop)
        // instead of with the real screen, and the image blends into the README.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let backdrop = NSWindow(contentRect: NSScreen.main?.frame ?? .zero, styleMask: .borderless,
                                backing: .buffered, defer: false)
        backdrop.title = "SwitchbackDemoBackdrop"   // the capture script skips it by name
        backdrop.backgroundColor = DemoData.backdropColor(dark: dark)
        // Just below what's captured: menus for the menu and window shots (the window
        // is raised to menu level), modal panels for the dialog, whose level NSAlert
        // sets itself when it runs.
        let below = what == "dialog" ? NSWindow.Level.modalPanel : NSWindow.Level.popUpMenu
        backdrop.level = NSWindow.Level(rawValue: below.rawValue - 1)
        backdrop.ignoresMouseEvents = true
        backdrop.orderFrontRegardless()
        Self.demoBackdrop = backdrop

        switch what {
        case "manage":
            showManageWindow()
            manageWindow?.window?.level = DemoData.uiLevel
            manageWindow?.window?.setContentSize(NSSize(width: 500, height: 236))   // fit four rows
            manageWindow?.debugSelect(row: 1)    // "Client Site A": shows selection and an enabled −
        case "dialog":
            NSApp.activate(ignoringOtherApps: true)
            // A new, valid name with OK enabled. Put the caret at the end instead of
            // selecting the text, so it reads as typing. NSAlert's modal loop fires
            // timers scheduled in the common modes, not queued main-queue blocks.
            let caret = Timer(timeInterval: 0.3, repeats: false) { _ in
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                }
            }
            RunLoop.main.add(caret, forMode: .common)
            _ = NameDialog(title: "New Location", message: "Name for the new network location:",
                           initial: "Client Site B", existing: existingNames()).run()
        default:
            statusItem.button?.performClick(nil)   // opens the menu
        }
    }

    /// The Manage Locations window's rows, built off-screen (debug flags `--manage`
    /// and `--manage-sample`, which uses made-up locations to cover every row kind).
    func debugManageDump(sample: Bool = false) -> [String] {
        let fake = [
            NetworkLocation(id: "a", name: "Automatic", isCurrent: false, serviceCount: 4, primaryService: "Wi-Fi"),
            NetworkLocation(id: "o", name: "Office", isCurrent: true, serviceCount: 2, primaryService: "Thunderbolt Ethernet Slot 0"),
            NetworkLocation(id: "c", name: "Client A", isCurrent: false, serviceCount: 1, primaryService: "Wi-Fi"),
            NetworkLocation(id: "e", name: "Empty", isCurrent: false, serviceCount: 0, primaryService: nil),
        ]
        let window = ManageLocationsWindowController(actions: .init(
            locations: { [self] in sample ? fake : locations },
            create: {}, rename: { _, _ in }, delete: { _ in }, reorder: { _ in }))
        return window.debugDump()
    }
}
#endif
