import Foundation
import SystemConfiguration
import Security

/// Primary backend: commits location changes via `SCPreferences` opened with an
/// `AuthorizationRef`, so macOS presents its native "is trying to make changes"
/// auth panel. No sudoers rule, no setup step — and notarizable.
///
/// Switching, creating, renaming and deleting locations are all privileged
/// commits through this same authorized-preferences path.
final class AuthorizedSwitcher: LocationSwitcher {

    /// The default location is special: it carries every detected service and is
    /// what the system falls back to. Renaming or deleting it can break networking,
    /// so we refuse both. Compared case-insensitively against the set name.
    private static let protectedName = "Automatic"

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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocationSwitcherError.emptyName }

        var newID = ""
        try withAuthorizedPrefs { prefs in
            guard !nameExists(name, in: prefs) else { throw LocationSwitcherError.duplicateName }
            guard let set = SCNetworkSetCreate(prefs) else { throw LocationSwitcherError.createFailed }
            guard SCNetworkSetSetName(set, name as CFString) else { throw LocationSwitcherError.createFailed }
            // Populate the new set with one default service per attached interface,
            // so it's usable immediately rather than an empty location with no
            // networking. This mirrors `networksetup -createlocation … populate`.
            populateDefaultServices(into: set, prefs: prefs)
            newID = (SCNetworkSetGetSetID(set) as String?) ?? ""
        }
        return newID
    }

    func renameLocation(locationID: String, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocationSwitcherError.emptyName }

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
            guard let set = set(withID: locationID, in: prefs) else {
                throw LocationSwitcherError.setNotFound
            }
            try guardNotProtected(set)
            guard SCNetworkSetRemove(set) else { throw LocationSwitcherError.commitFailed }
        }
    }

    // MARK: - Privileged plumbing

    /// Open authorized preferences, run `body`, then commit + apply. The single
    /// auth panel covers everything `body` mutates. `body` throws to abort before commit.
    private func withAuthorizedPrefs(_ body: (SCPreferences) throws -> Void) throws {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil,
                                         [.interactionAllowed, .extendRights, .preAuthorize],
                                         &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw LocationSwitcherError.authorizationFailed
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "Switchback" as CFString, nil, auth) else {
            throw LocationSwitcherError.preferencesUnavailable
        }

        try body(prefs)

        guard SCPreferencesCommitChanges(prefs) else { throw LocationSwitcherError.commitFailed }
        guard SCPreferencesApplyChanges(prefs) else { throw LocationSwitcherError.applyFailed }
    }

    /// Add a default-configured service for every attached interface to `set`,
    /// giving a freshly created location working networking. Best-effort per
    /// interface: a single interface that won't configure is skipped, not fatal.
    private func populateDefaultServices(into set: SCNetworkSet, prefs: SCPreferences) {
        let interfaces = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? []
        for interface in interfaces {
            guard let service = SCNetworkServiceCreate(prefs, interface) else { continue }
            SCNetworkServiceEstablishDefaultConfiguration(service)
            SCNetworkSetAddService(set, service)
        }
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
