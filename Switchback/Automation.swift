import Foundation

extension Notification.Name {
    /// Posted after Shortcuts or a Focus switches location, so the menu and window
    /// refresh (and flash the new name) even if the change wasn't otherwise noticed.
    static let switchbackLocationChanged = Notification.Name("com.breed007.switchback.locationChanged")
}

/// What happens when Shortcuts or a Focus asks for a switch (F7). Free of App
/// Intents, so the rules are unit-tested with fakes:
///
/// - Already on that location: do nothing, announce nothing.
/// - A shortcut switches through the router, so without the helper it falls back
///   to the admin prompt; someone ran it and is there to answer.
/// - A Focus changes with nobody watching, so it never prompts. Without the helper
///   it skips the switch and posts a notification saying how to enable it. If the
///   helper refuses or fails, it says so instead of retrying through a prompt.
/// - Every automated switch is announced (F6), which keeps DESIGN.md's "no surprise
///   network changes" promise.
struct AutomationSwitch {
    enum Source: Equatable { case shortcut, focus }

    enum Announcement: Equatable {
        case switched(name: String, source: Source)
        case helperNeeded
        case focusFailed(name: String)
    }

    enum Outcome: Equatable { case alreadyCurrent, switched, needsHelper, failed }

    var currentID: () -> String?
    var helperEnabled: () -> Bool
    /// Through the router (helper, else the admin prompt).
    var routedSwitch: (String) async throws -> Void
    /// The helper only; never prompts.
    var helperSwitch: (String) async throws -> Void
    var announce: (Announcement) async -> Void

    /// Throws only for a shortcut (Shortcuts shows the error). A Focus failure is
    /// announced instead, since nobody would see a thrown error.
    func run(id: String, name: String, source: Source) async throws -> Outcome {
        if currentID() == id { return .alreadyCurrent }
        switch source {
        case .shortcut:
            try await routedSwitch(id)
        case .focus:
            guard helperEnabled() else {
                await announce(.helperNeeded)
                return .needsHelper
            }
            do {
                try await helperSwitch(id)
            } catch {
                await announce(.focusFailed(name: name))
                return .failed
            }
        }
        await announce(.switched(name: name, source: source))
        return .switched
    }

    /// The real backends.
    static let live = AutomationSwitch(
        currentID: { StatusMonitor.readLocations().first(where: \.isCurrent)?.id },
        helperEnabled: { HelperClient.isEnabled },
        routedSwitch: { try await SwitchRouter.shared.switchTo(locationID: $0) },
        helperSwitch: { try await HelperClient.switchTo(setID: $0) },
        announce: { announcement in
            if case .switched = announcement {
                await MainActor.run { NotificationCenter.default.post(name: .switchbackLocationChanged, object: nil) }
            }
            await SwitchNotifier.post(announcement)
        })
}

/// Matching for "Switch to <name>" in Shortcuts and Siri: case, full-width letters,
/// and invisible characters don't matter (the name skeleton from F3).
enum LocationSearch {
    static func matches(_ name: String, query: String) -> Bool {
        let key = LocationNameValidator.skeleton(query)
        return key.isEmpty || LocationNameValidator.skeleton(name).contains(key)
    }
}
