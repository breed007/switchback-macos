import Foundation

/// The helper's switching policy. By default any local user may switch between
/// existing locations. IT can require admin rights with a managed preference:
/// `RequireAdminToSwitch` (Bool) in the computer-level managed preferences domain.
///
/// Compiled into the helper (which enforces it), the app (debug diagnostics), and
/// the unit tests.
enum HelperPolicy {
    static let managedPreferencesPath = "/Library/Managed Preferences/com.breed007.switchback.plist"
    static let requireAdminKey = "RequireAdminToSwitch"

    /// The managed `RequireAdminToSwitch` value; false if unset. Only a root-owned
    /// file counts: the managed-preferences folder is written by the MDM client,
    /// never by a standard user, and user-writable defaults are never consulted.
    static func requireAdminToSwitch(plistPath: String = managedPreferencesPath,
                                      requireRootOwner: Bool = true) -> Bool {
        if requireRootOwner {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: plistPath),
                  (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0 else { return false }
        }
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return false }
        return (dict[requireAdminKey] as? Bool) ?? false
    }

    /// Whether `uid` is in the admin group, as resolved by the system's membership
    /// service. Unknown users count as non-admin.
    static func isAdmin(uid: uid_t) -> Bool {
        guard let user = getpwuid(uid) else { return false }
        let adminGID = getgrnam("admin")?.pointee.gr_gid ?? 80
        var count: Int32 = 256
        var groups = [Int32](repeating: 0, count: Int(count))
        guard getgrouplist(user.pointee.pw_name, Int32(bitPattern: user.pointee.pw_gid),
                           &groups, &count) != -1 else { return false }
        return groups.prefix(Int(count)).contains(Int32(bitPattern: adminGID))
    }

    /// The decision itself, kept separate so it's trivially testable.
    static func allows(requireAdmin: Bool, callerIsAdmin: Bool) -> Bool {
        !requireAdmin || callerIsAdmin
    }
}
