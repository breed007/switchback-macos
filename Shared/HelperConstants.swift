import Foundation

/// Constants shared by the app (client) and SwitchbackHelper (server). Compiled
/// into both targets: the Mach service name and the code-signing requirements
/// must match on both ends or the connection can't form.
enum HelperConstants {
    /// The helper's Mach service name (matches its launchd plist).
    static let machServiceName = "com.breed007.switchback.helper"

    /// The helper's bundle identifier, embedded in its binary's Info.plist.
    static let helperBundleID = "com.breed007.switchback.helper"

    /// The launchd plist inside `Contents/Library/LaunchDaemons`.
    static let plistName = "com.breed007.switchback.helper.plist"

    static let appBundleID = "com.breed007.switchback"

    /// Developer ID team that signs both ends.
    static let teamID = "YA83Q8FTH3"

    /// Requirement the helper enforces on every client: the Switchback app,
    /// signed by our team. The OS checks it per message, before helper code runs.
    static let clientRequirement =
        "identifier \"\(appBundleID)\" and anchor apple generic and " +
        "certificate leaf[subject.OU] = \"\(teamID)\""

    /// Requirement the app enforces on the helper. SMAppService already
    /// guarantees provenance; pinning costs nothing.
    static let helperRequirement =
        "identifier \"\(helperBundleID)\" and anchor apple generic and " +
        "certificate leaf[subject.OU] = \"\(teamID)\""

    /// XPC message keys.
    enum Key {
        static let op = "op"            // string (request)
        static let setID = "setID"      // string (request): the target SCNetworkSet ID
        static let ok = "ok"            // bool (reply)
        static let error = "error"      // string (reply, on failure)
    }

    /// The helper's only operation. It switches locations and nothing else.
    static let opSwitchTo = "switchTo"
}
