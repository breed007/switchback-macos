import Foundation
import SystemConfiguration
import Security

/// Primary backend: commits location changes via `SCPreferences` opened with an
/// `AuthorizationRef`, so macOS presents its native "is trying to make changes"
/// auth panel. No sudoers rule, no setup step — and notarizable.
///
/// Switching, creating, renaming and deleting locations are all privileged
/// commits through this same authorized-preferences path.
///
/// These methods run the privileged commit synchronously; callers should invoke
/// them off the main thread so the menu-bar UI doesn't block while macOS applies
/// the new network configuration.
final class AuthorizedSwitcher: LocationSwitcher {

    /// The default location is special: it carries every detected service and is
    /// what the system falls back to. Renaming or deleting it can break networking,
    /// so we refuse both. Compared case-insensitively against the set name.
    private static let protectedName = "Automatic"

    /// Upper bound on a location name. macOS tolerates long names, but an
    /// unbounded paste (a signature block, a wall of text) makes an unusable menu
    /// item and a name the `scselect` CLI chokes on.
    private static let maxNameLength = 128

    // MARK: - LocationSwitcher

    func switchTo(locationID: String) throws {
        try withAuthorizedPrefs { prefs in
            guard let target = set(withID: locationID, in: prefs) else {
                throw LocationSwitcherError.setNotFound
            }
            guard SCNetworkSetSetCurrent(target) else { throw LocationSwitcherError.commitFailed }
        }
    }

    @discardableResult
    func createLocation(named rawName: String) throws -> String {
        let name = try cleanName(rawName)

        var newID = ""
        try withAuthorizedPrefs { prefs in
            guard !nameExists(name, in: prefs) else { throw LocationSwitcherError.duplicateName }
            guard let set = SCNetworkSetCreate(prefs) else { throw LocationSwitcherError.createFailed }
            guard SCNetworkSetSetName(set, name as CFString) else { throw LocationSwitcherError.createFailed }
            // Populate with one default service per attached interface, mirroring
            // `networksetup -createlocation … populate`. If nothing could be added
            // the location would be an empty, non-functional set — refuse it.
            guard populateDefaultServices(into: set, prefs: prefs) > 0 else {
                throw LocationSwitcherError.createFailed
            }
            newID = (SCNetworkSetGetSetID(set) as String?) ?? ""
        }
        return newID
    }

    func renameLocation(locationID: String, to rawName: String) throws {
        let name = try cleanName(rawName)

        try withAuthorizedPrefs { prefs in
            guard let set = set(withID: locationID, in: prefs) else {
                throw LocationSwitcherError.setNotFound
            }
            try guardNotProtected(set)
            // Allow renaming a set to the same name (a no-op); reject collisions with others.
            let current = SCNetworkSetGetName(set) as String?
            if name.compare(current ?? "", options: .caseInsensitive) != .orderedSame,
               nameExists(name, in: prefs) {
                throw LocationSwitcherError.duplicateName
            }
            guard SCNetworkSetSetName(set, name as CFString) else { throw LocationSwitcherError.commitFailed }
        }
    }

    func deleteLocation(locationID: String) throws {
        try withAuthorizedPrefs { prefs in
            let all = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
            guard let set = all.first(where: { (SCNetworkSetGetSetID($0) as String?) == locationID }) else {
                throw LocationSwitcherError.setNotFound
            }
            try guardNotProtected(set)
            // Identity-based safety, independent of the name: never leave the system
            // with zero sets, and never delete the set that's currently active.
            guard all.count > 1 else { throw LocationSwitcherError.cannotDeleteLast }
            let currentID = SCNetworkSetCopyCurrent(prefs).flatMap { SCNetworkSetGetSetID($0) as String? }
            guard currentID != locationID else { throw LocationSwitcherError.cannotDeleteCurrent }
            guard SCNetworkSetRemove(set) else { throw LocationSwitcherError.commitFailed }
        }
    }

    // MARK: - Privileged plumbing

    /// Open authorized preferences, run `body`, then commit + apply. The single
    /// auth panel covers everything `body` mutates. `body` throws to abort before
    /// commit. If the user declines the panel, this throws `.cancelled`.
    private func withAuthorizedPrefs(_ body: (SCPreferences) throws -> Void) throws {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil,
                                         [.interactionAllowed, .extendRights, .preAuthorize],
                                         &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw status == errAuthorizationCanceled
                ? LocationSwitcherError.cancelled
                : LocationSwitcherError.authorizationFailed
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "Switchback" as CFString, nil, auth) else {
            throw LocationSwitcherError.preferencesUnavailable
        }

        try body(prefs)

        guard SCPreferencesCommitChanges(prefs) else {
            throw wasAuthCancelled() ? LocationSwitcherError.cancelled : LocationSwitcherError.commitFailed
        }
        guard SCPreferencesApplyChanges(prefs) else {
            throw wasAuthCancelled() ? LocationSwitcherError.cancelled : LocationSwitcherError.applyFailed
        }
    }

    /// When the user clicks Cancel on the auth panel, the commit fails with an
    /// access error rather than throwing — distinguish that from a real failure so
    /// the UI can treat a cancel as a silent no-op.
    private func wasAuthCancelled() -> Bool {
        SCError() == kSCStatusAccessError
    }

    /// Add a default-configured service for every attached interface to `set`,
    /// giving a freshly created location working networking. Best-effort per
    /// interface; returns how many services were actually added.
    private func populateDefaultServices(into set: SCNetworkSet, prefs: SCPreferences) -> Int {
        let interfaces = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? []
        var added = 0
        for interface in interfaces {
            guard let service = SCNetworkServiceCreate(prefs, interface) else { continue }
            SCNetworkServiceEstablishDefaultConfiguration(service)
            if SCNetworkSetAddService(set, service) { added += 1 }
        }
        return added
    }

    /// Trim, strip control characters (including embedded newlines/tabs), and
    /// bound the length. Throws `.emptyName` / `.nameTooLong` on rejection.
    private func cleanName(_ raw: String) throws -> String {
        let stripped = raw.components(separatedBy: .controlCharacters).joined(separator: " ")
        let name = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocationSwitcherError.emptyName }
        guard name.count <= Self.maxNameLength else { throw LocationSwitcherError.nameTooLong }
        return name
    }

    private func set(withID id: String, in prefs: SCPreferences) -> SCNetworkSet? {
        let all = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
        return all.first { (SCNetworkSetGetSetID($0) as String?) == id }
    }

    private func nameExists(_ name: String, in prefs: SCPreferences) -> Bool {
        let all = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
        return all.contains { set in
            guard let existing = SCNetworkSetGetName(set) as String? else { return false }
            return existing.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    private func guardNotProtected(_ set: SCNetworkSet) throws {
        let name = SCNetworkSetGetName(set) as String? ?? ""
        if name.compare(Self.protectedName, options: .caseInsensitive) == .orderedSame {
            throw LocationSwitcherError.protectedLocation
        }
    }
}
