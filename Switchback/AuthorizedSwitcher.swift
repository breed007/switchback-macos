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
        var newID = ""
        try withAuthorizedPrefs { prefs in
            let name = try validatedName(rawName, in: prefs, excludingID: nil)
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
        try withAuthorizedPrefs { prefs in
            guard let set = set(withID: locationID, in: prefs) else {
                throw LocationSwitcherError.setNotFound
            }
            try guardNotProtected(set)
            // Excluding this location's own ID allows a case-only rename.
            let name = try validatedName(rawName, in: prefs, excludingID: locationID)
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
    /// commit. If the user declines the panel, this throws `.canceled`.
    private func withAuthorizedPrefs(_ body: (SCPreferences) throws -> Void) throws {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil,
                                         [.interactionAllowed, .extendRights, .preAuthorize],
                                         &authRef)
        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw status == errAuthorizationCanceled
                ? LocationSwitcherError.canceled
                : LocationSwitcherError.authorizationFailed
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }

        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "Switchback" as CFString, nil, auth) else {
            throw LocationSwitcherError.preferencesUnavailable
        }

        try body(prefs)

        guard SCPreferencesCommitChanges(prefs) else {
            throw wasAuthCanceled() ? LocationSwitcherError.canceled : LocationSwitcherError.commitFailed
        }
        guard SCPreferencesApplyChanges(prefs) else {
            throw wasAuthCanceled() ? LocationSwitcherError.canceled : LocationSwitcherError.applyFailed
        }
    }

    /// When the user clicks Cancel on the auth panel, the commit fails with an
    /// access error rather than throwing — distinguish that from a real failure so
    /// the UI can treat a cancel as a silent no-op.
    private func wasAuthCanceled() -> Bool {
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

    /// Validate `raw` against the live locations (the authoritative check; the UI
    /// checks too, but a location can appear between the dialog and the commit).
    private func validatedName(_ raw: String, in prefs: SCPreferences, excludingID: String?) throws -> String {
        let existing = ((SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []).compactMap { set -> LocationNameValidator.Existing? in
            guard let id = SCNetworkSetGetSetID(set) as String?,
                  let name = SCNetworkSetGetName(set) as String? else { return nil }
            return LocationNameValidator.Existing(id: id, name: name)
        }
        let result = LocationNameValidator.validate(raw, existing: existing, excludingID: excludingID)
        switch result.problem {
        case nil:        return result.name
        case .empty:     throw LocationSwitcherError.emptyName
        case .tooLong:   throw LocationSwitcherError.nameTooLong
        case .reserved:  throw LocationSwitcherError.reservedName
        case .duplicate: throw LocationSwitcherError.duplicateName
        }
    }

    private func set(withID id: String, in prefs: SCPreferences) -> SCNetworkSet? {
        let all = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
        return all.first { (SCNetworkSetGetSetID($0) as String?) == id }
    }

    private func guardNotProtected(_ set: SCNetworkSet) throws {
        if LocationNameValidator.isReserved(SCNetworkSetGetName(set) as String? ?? "") {
            throw LocationSwitcherError.protectedLocation
        }
    }
}
