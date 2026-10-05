import Foundation
import SystemConfiguration

/// The live details shown under the current location in the menu: primary service,
/// address, and DNS servers. Read from the dynamic store; no privileges needed.
struct NetworkDetails: Equatable {
    var service: String?
    var address: String?
    var dns: [String] = []

    /// "Wi-Fi · 10.0.4.22 · DNS 10.0.0.1, 1.1.1.1", or "Not connected".
    var summary: String {
        guard service != nil || address != nil else { return "Not connected" }
        var parts: [String] = []
        if let service { parts.append(service) }
        if let address { parts.append(address) }
        if !dns.isEmpty { parts.append("DNS " + dns.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func current() -> NetworkDetails {
        #if DEBUG
        if DemoData.active { return DemoData.details }
        #endif
        guard let store = SCDynamicStoreCreate(nil, "Switchback" as CFString, nil, nil) else {
            return NetworkDetails()
        }
        func value(_ key: String) -> [String: Any]? {
            SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
        }

        // IPv4's primary service, or IPv6's on an IPv6-only network.
        let primaryID = (value("State:/Network/Global/IPv4")?["PrimaryService"]
                         ?? value("State:/Network/Global/IPv6")?["PrimaryService"]) as? String
        var details = NetworkDetails()
        if let id = primaryID {
            details.service = value("Setup:/Network/Service/\(id)")?["UserDefinedName"] as? String
            details.address = (value("State:/Network/Service/\(id)/IPv4")?["Addresses"] as? [String])?.first
                ?? (value("State:/Network/Service/\(id)/IPv6")?["Addresses"] as? [String])?
                    .first { !$0.lowercased().hasPrefix("fe80") }
        }
        details.dns = (value("State:/Network/Global/DNS")?["ServerAddresses"] as? [String]) ?? []
        return details
    }
}
