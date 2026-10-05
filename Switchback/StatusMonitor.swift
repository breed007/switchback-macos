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
        guard let prefs = SCPreferencesCreate(nil, "Switchback" as CFString, nil) else {
            locations = []
            return
        }
        let current = SCNetworkSetCopyCurrent(prefs)
        let currentID = current.flatMap { SCNetworkSetGetSetID($0) as String? }

        let all = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
        locations = all.compactMap { set -> NetworkLocation? in
            guard let id = SCNetworkSetGetSetID(set) as String?,
                  let name = SCNetworkSetGetName(set) as String? else { return nil }
            let enabled = ((SCNetworkSetCopyServices(set) as? [SCNetworkService]) ?? [])
                .filter { SCNetworkServiceGetEnabled($0) && !isHidden($0) }
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

    /// Services on interfaces macOS hides from its settings don't count.
    private var hiddenCache: [String: Bool] = [:]
    private func isHidden(_ service: SCNetworkService) -> Bool {
        guard let bsd = SCNetworkServiceGetInterface(service).flatMap({ SCNetworkInterfaceGetBSDName($0) as String? })
        else { return false }   // e.g. VPN services have no BSD interface
        if let known = hiddenCache[bsd] { return known }
        let hidden = HiddenInterfaces.isHidden(bsdName: bsd)
        hiddenCache[bsd] = hidden
        return hidden
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
