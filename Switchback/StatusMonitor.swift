import Foundation
import SystemConfiguration

/// Event-driven, unprivileged reader of network locations. Subscribes to
/// `SCDynamicStore` and refreshes the model only when state actually changes
/// (no polling). Mirrors Crossbar's `StatusMonitor`.
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
            return NetworkLocation(id: id, name: name, isCurrent: id == currentID)
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
        // The current set lives under Setup:/ ; watch it for switches made elsewhere too.
        let keys = ["Setup:/" as CFString, "Setup:/Network/Global/IPv4" as CFString]
        SCDynamicStoreSetNotificationKeys(store, keys as CFArray, nil)
        if let src = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        self.store = store
    }
}
