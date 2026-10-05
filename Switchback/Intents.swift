import AppIntents
import os

/// Every automation run is logged (set IDs only), so what macOS delivers, such as
/// a Focus filter's call when the Focus ends, can be checked afterward with
/// `/usr/bin/log show --predicate 'subsystem == "com.breed007.switchback" AND category == "automation"'`.
private let automationLog = Logger(subsystem: HelperConstants.appBundleID, category: "automation")

// Shortcuts, Spotlight, Siri, and Focus integration (F7). These live in the app
// target, not an extension, so the helper's caller check (one signing identifier)
// covers them. The rules are in AutomationSwitch; this file is the App Intents shell.

/// A network location as Shortcuts, Spotlight, and Focus see it.
struct LocationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Network Location"
    static let defaultQuery = LocationQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ location: NetworkLocation) {
        self.init(id: location.id, name: location.name)
    }
}

struct LocationQuery: EntityStringQuery {
    /// Every location, in the user's order (F5).
    private func all() -> [LocationEntity] {
        LocationOrder.apply(LocationOrder().ids, to: StatusMonitor.readLocations()).map(LocationEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [LocationEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [LocationEntity] {
        all().filter { LocationSearch.matches($0.name, query: string) }
    }

    func suggestedEntities() async throws -> [LocationEntity] {
        all()
    }
}

/// "Switch Network Location": switch to a location, through the helper when it's
/// set up, otherwise with the admin prompt.
struct SwitchLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Network Location"
    static let description: IntentDescription? = IntentDescription("Switches your Mac to a network location.")
    static let openAppWhenRun = false

    @Parameter(title: "Location")
    var location: LocationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$location)")
    }

    init() {}

    init(location: LocationEntity) {
        self.location = location
    }

    func perform() async throws -> some IntentResult & ReturnsValue<LocationEntity> & ProvidesDialog {
        let outcome = try await AutomationSwitch.live.run(id: location.id, name: location.name, source: .shortcut)
        automationLog.notice("shortcut asked for \(location.id, privacy: .public): \(String(describing: outcome), privacy: .public)")
        let message = outcome == .alreadyCurrent ? "Already on \(location.name)." : "Switched to \(location.name)."
        return .result(value: location, dialog: "\(message)")
    }
}

/// "Get Current Network Location": for Shortcuts conditions.
struct GetCurrentLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Network Location"
    static let description: IntentDescription? = IntentDescription("Returns the network location your Mac is using.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<LocationEntity> & ProvidesDialog {
        guard let current = StatusMonitor.readLocations().first(where: \.isCurrent) else {
            throw LocationSwitcherError.setNotFound
        }
        let entity = LocationEntity(current)
        return .result(value: entity, dialog: "\(entity.name)")
    }
}

/// A Focus filter: in a Focus's settings, pick a location to switch to when that
/// Focus turns on. Ending the Focus changes nothing.
struct SwitchbackFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Switch Network Location"
    static let description: IntentDescription? = IntentDescription(
        "Switches to a network location when this Focus turns on. Turning the Focus off doesn\u{2019}t change it.")

    /// Optional and nil by default, so whatever the system sends when a Focus ends
    /// (or a filter with no location) causes no switch.
    @Parameter(title: "Location")
    var location: LocationEntity?

    var displayRepresentation: DisplayRepresentation {
        let text = location.map { "Switch to \($0.name)" } ?? "Don\u{2019}t switch"
        return DisplayRepresentation(title: "\(text)")
    }

    func perform() async throws -> some IntentResult {
        guard let location else {
            automationLog.notice("focus filter ran with no location (Focus ended, or none chosen): no change")
            return .result()
        }
        let outcome = try await AutomationSwitch.live.run(id: location.id, name: location.name, source: .focus)
        automationLog.notice("focus filter asked for \(location.id, privacy: .public): \(String(describing: outcome), privacy: .public)")
        return .result()
    }
}

/// Spotlight and Siri phrases. Global keyboard shortcuts come from Shortcuts itself,
/// which can assign a key combination to a Switch Network Location shortcut.
struct SwitchbackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SwitchLocationIntent(), phrases: [
            "Switch \(.applicationName) location to \(\.$location)",
            "Switch to \(\.$location) with \(.applicationName)",
        ], shortTitle: "Switch Location", systemImageName: "arrow.triangle.branch")
        AppShortcut(intent: GetCurrentLocationIntent(), phrases: [
            "What\u{2019}s my \(.applicationName) location",
            "Get \(.applicationName) location",
        ], shortTitle: "Current Location", systemImageName: "network")
    }
}
