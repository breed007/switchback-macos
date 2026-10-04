import Foundation

/// Sends switches through the privileged helper when it's enabled, so they need no
/// password. Creating, renaming, and deleting always use the admin-authorized
/// backend, because they change configuration.
///
/// Spike version: helper errors surface as-is rather than falling back to the admin
/// prompt, so failures are visible. Fallback and policy land in milestone 3.
final class SwitchRouter: LocationSwitcher {
    private let authorized = AuthorizedSwitcher()

    func switchTo(locationID: String) throws {
        if HelperClient.isEnabled {
            try HelperClient.switchTo(setID: locationID)
        } else {
            try authorized.switchTo(locationID: locationID)
        }
    }

    @discardableResult
    func createLocation(named name: String) throws -> String {
        try authorized.createLocation(named: name)
    }

    func renameLocation(locationID: String, to name: String) throws {
        try authorized.renameLocation(locationID: locationID, to: name)
    }

    func deleteLocation(locationID: String) throws {
        try authorized.deleteLocation(locationID: locationID)
    }
}
