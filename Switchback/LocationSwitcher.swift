import Foundation

/// The privilege seam. The UI only ever talks to this protocol, so the
/// privileged backend can be swapped (e.g. for an XPC/SMAppService helper)
/// without touching the interface. Mirrors Crossbar's `PrivilegedToggle`.
protocol LocationSwitcher {
    /// Switch the current network location to the set with the given ID.
    func switchTo(locationID: String) throws

    /// Create a new location, populated with the system's default services
    /// (one per attached interface), and return its new set ID.
    @discardableResult
    func createLocation(named name: String) throws -> String

    /// Rename the location with the given ID.
    func renameLocation(locationID: String, to name: String) throws

    /// Delete the location with the given ID.
    func deleteLocation(locationID: String) throws
}

enum LocationSwitcherError: Error, CustomStringConvertible {
    case authorizationFailed
    case preferencesUnavailable
    case setNotFound
    case commitFailed
    case applyFailed
    case createFailed
    case duplicateName
    case emptyName
    case protectedLocation

    var description: String {
        switch self {
        case .authorizationFailed:  return "Authorization was not granted."
        case .preferencesUnavailable: return "Could not open network preferences."
        case .setNotFound:          return "That location no longer exists."
        case .commitFailed:         return "Could not commit the change."
        case .applyFailed:          return "Could not apply the change."
        case .createFailed:         return "Could not create the location."
        case .duplicateName:        return "A location with that name already exists."
        case .emptyName:            return "Please enter a location name."
        case .protectedLocation:    return "The \u{201C}Automatic\u{201D} location can\u{2019}t be renamed or deleted."
        }
    }
}
