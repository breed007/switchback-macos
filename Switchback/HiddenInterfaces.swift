import Foundation
import IOKit
import SystemConfiguration

/// macOS hides some network interfaces from its settings: on Apple silicon, for
/// example, the internal USB-C networking interfaces (`AppleUSBDeviceNCM11Data`,
/// usually en4–en6). Their drivers carry `HiddenConfiguration = Yes` in the I/O
/// Registry. Switchback skips services on those interfaces so its service counts
/// match System Settings and `networksetup`.
enum HiddenInterfaces {
    private static var cache: [String: Bool] = [:]
    private static let lock = NSLock()

    /// Whether a service sits on a hidden interface. Services without a BSD
    /// interface (VPN, for example) are never hidden. Cached per interface; safe
    /// from any thread.
    static func isHidden(_ service: SCNetworkService) -> Bool {
        guard let bsd = SCNetworkServiceGetInterface(service).flatMap({ SCNetworkInterfaceGetBSDName($0) as String? })
        else { return false }
        lock.lock(); defer { lock.unlock() }
        if let known = cache[bsd] { return known }
        let hidden = isHidden(bsdName: bsd)
        cache[bsd] = hidden
        return hidden
    }

    /// Whether the interface with this BSD name (e.g. "en4") is hidden. Interfaces
    /// with no registry entry (virtual ones such as bridge0) are not hidden.
    static func isHidden(bsdName: String) -> Bool {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return false }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)   // consumes `matching`
        guard entry != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(entry) }
        // The flag lives on the driver, a parent of the interface object.
        let value = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "HiddenConfiguration" as CFString,
                                                    kCFAllocatorDefault,
                                                    IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        return (value as? Bool) == true
    }
}
