import Foundation
import os

/// Sends switches through the privileged helper when it's enabled, so they need no
/// password. If the helper can't be reached, refuses by policy, or is too old to
/// know the request, the switch falls back to the admin prompt. Creating,
/// renaming, and deleting always use the admin-authorized backend, because they
/// change configuration.
final class SwitchRouter: LocationSwitcher {
    private let authorized: LocationSwitcher
    private let helperEnabled: () -> Bool
    private let helperSwitch: (String) async throws -> Void
    private let log = Logger(subsystem: HelperConstants.appBundleID, category: "router")

    /// The defaults are the real backends; tests inject fakes.
    init(authorized: LocationSwitcher = AuthorizedSwitcher(),
         helperEnabled: @escaping () -> Bool = { HelperClient.isEnabled },
         helperSwitch: @escaping (String) async throws -> Void = { try await HelperClient.switchTo(setID: $0) }) {
        self.authorized = authorized
        self.helperEnabled = helperEnabled
        self.helperSwitch = helperSwitch
    }

    func switchTo(locationID: String) async throws {
        guard helperEnabled() else {
            return try await authorized.switchTo(locationID: locationID)
        }
        do {
            try await helperSwitch(locationID)
        } catch let error as HelperError where error.allowsFallback {
            log.notice("helper didn't switch (\(error.description, privacy: .public)); using the admin prompt")
            try await authorized.switchTo(locationID: locationID)
        }
    }

    @discardableResult
    func createLocation(named name: String) async throws -> String {
        try await authorized.createLocation(named: name)
    }

    func renameLocation(locationID: String, to name: String) async throws {
        try await authorized.renameLocation(locationID: locationID, to: name)
    }

    func deleteLocation(locationID: String) async throws {
        try await authorized.deleteLocation(locationID: locationID)
    }
}
