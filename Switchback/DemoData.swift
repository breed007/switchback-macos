#if DEBUG
import AppKit

/// Sample data for README screenshots (`Switchback --demo`). With `active` set, the
/// real menu and Manage Locations window show these instead of the Mac's own
/// locations and network details, so no real IPs or VPN names end up in a picture.
/// Debug builds only; compiled out of releases.
enum DemoData {
    static var active = false

    /// In the order the menu shows them (Office first, so the custom order shows).
    static let locations: [NetworkLocation] = [
        NetworkLocation(id: "demo-office", name: "Office", isCurrent: true, serviceCount: 3, primaryService: "Ethernet"),
        NetworkLocation(id: "demo-client", name: "Client Site A", isCurrent: false, serviceCount: 2, primaryService: "Wi-Fi"),
        NetworkLocation(id: "demo-home", name: "Home", isCurrent: false, serviceCount: 2, primaryService: "Wi-Fi"),
        NetworkLocation(id: "demo-auto", name: "Automatic", isCurrent: false, serviceCount: 4, primaryService: "Wi-Fi"),
    ]

    static let order = locations.map(\.id)

    /// GitHub's README background, light and dark, so captures blend into the page.
    static func backdropColor(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1) : .white
    }

    /// Above the backdrop (which sits just below menus).
    static let uiLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue)

    /// Private (RFC 1918) addresses, not this Mac's.
    static let details = NetworkDetails(service: "Ethernet", address: "10.20.30.45", dns: ["10.20.0.53", "10.20.0.54"])
}
#endif
