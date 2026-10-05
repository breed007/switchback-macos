import Foundation
import SystemConfiguration

/// Unprivileged reader of network locations. The status item calls `reload()`
/// each time the menu opens; that read is the source of truth. The current-set
/// pointer lives in the preferences plist (`CurrentSet`) and is not an
/// `SCDynamicStore` key, so the subscription below can't see every switch. It's
/// kept only for live updates while the menu is open (no polling).
/// Mirrors Crossbar's `StatusMonitor`.
final class StatusMonitor {
    private(set) var locations: [NetworkLocation] = []
    var onChange: (() -> Void)?

    private var store: SCDynamicStore?

    init() {
        setupDynamicStore()
        reload()
    }

    func reload() {
        locations = Self.readLocations()
    }

    /// Read every location from the preferences, alphabetically. No privileges and
    /// no run-loop hookup, so Shortcuts and Focus can call it from any thread.
    static func readLocations() -> [NetworkLocation] {
        guard let prefs = SCPreferencesCreate(nil, "Switchback" as CFString, nil) else { return [] }
        let currentID = SCNetworkSetCopyCurrent(prefs).flatMap { SCNetworkSetGetSetID($0) as String? }
        let all = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
        return all.compactMap { set -> NetworkLocation? in
            guard let id = SCNetworkSetGetSetID(set) as String?,
                  let name = SCNetworkSetGetName(set) as String? else { return nil }
            // Services on interfaces macOS hides from its settings don't count.
            let enabled = ((SCNetworkSetCopyServices(set) as? [SCNetworkService]) ?? [])
                .filter { SCNetworkServiceGetEnabled($0) && !HiddenInterfaces.isHidden($0) }
            let order = (SCNetworkSetGetServiceOrder(set) as? [String]) ?? []
            let primary = order.lazy.compactMap { serviceID in
                enabled.first { (SCNetworkServiceGetServiceID($0) as String?) == serviceID }
            }.first ?? enabled.first
            return NetworkLocation(id: id, name: name, isCurrent: id == currentID,
                                   serviceCount: enabled.count,
                                   primaryService: primary.flatMap { SCNetworkServiceGetName($0) as String? })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func setupDynamicStore() {
        var context = SCDynamicStoreContext(version: 0, info: nil, retain: nil,
                                            release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info = info else { return }
            let monitor = Unmanaged<StatusMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.reload()
            monitor.onChange?()
        }

        guard let store = SCDynamicStoreCreate(nil, "Switchback" as CFString, callback, &context) else { return }
        // A switch usually changes the global IPv4 setup and state, so these catch
        // most switches made elsewhere. Not all: two locations with the same IPv4
        // setup produce no change here, which is why menuWillOpen re-reads.
        let keys = ["Setup:/Network/Global/IPv4" as CFString,
                    "State:/Network/Global/IPv4" as CFString]
        SCDynamicStoreSetNotificationKeys(store, keys as CFArray, nil)
        if let src = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        self.store = store
    }
}
