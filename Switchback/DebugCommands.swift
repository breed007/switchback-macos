#if DEBUG
import Foundation
import SystemConfiguration

/// Debug-only command-line hooks for exercising the helper from Terminal. They run
/// inside the signed Switchback binary, which is the only caller the helper
/// accepts, so `/Applications/Switchback.app/Contents/MacOS/Switchback <flag>`
/// tests the real path.
///
///   --helper-status            print the SMAppService status
///   --helper-register          register the helper (then approve in System Settings)
///   --helper-unregister        remove it
///   --helper-switch <setID>    switch through the helper
///   --helper-selftest          no-op switch to the current set, then an unknown set
enum DebugCommands {
    /// Returns an exit code if a debug flag was handled, or nil to launch normally.
    static func run(_ args: [String]) -> Int32? {
        guard args.count >= 2, args[1].hasPrefix("--helper-") else { return nil }

        switch args[1] {
        case "--helper-status":
            print("helper status: \(HelperClient.status.label)")
            return 0

        case "--helper-register":
            return attempt("register") { try HelperClient.register() }

        case "--helper-unregister":
            return attempt("unregister") { try HelperClient.unregister() }

        case "--helper-switch":
            guard args.count >= 3 else { print("usage: --helper-switch <setID>"); return 64 }
            return attempt("switch to \(args[2])") { try HelperClient.switchTo(setID: args[2]) }

        case "--helper-selftest":
            guard let current = currentSetID() else { print("FAIL: can't read current set"); return 1 }
            let noOp = attempt("no-op switch to current set \(current)") {
                try HelperClient.switchTo(setID: current)
            }
            var unknownOK = false
            do {
                try HelperClient.switchTo(setID: "00000000-0000-0000-0000-000000000000")
                print("FAIL: unknown set was accepted")
            } catch HelperError.helperReported(let code) where code == "unknown-set" {
                print("ok: unknown set rejected with unknown-set")
                unknownOK = true
            } catch {
                print("FAIL: unknown set: \(error)")
            }
            return (noOp == 0 && unknownOK) ? 0 : 1

        default:
            print("unknown flag \(args[1])")
            return 64
        }
    }

    private static func attempt(_ label: String, _ work: () throws -> Void) -> Int32 {
        do {
            try work()
            print("ok: \(label) (status now \(HelperClient.status.label))")
            return 0
        } catch {
            print("FAIL: \(label): \(error) (status \(HelperClient.status.label))")
            return 1
        }
    }

    private static func currentSetID() -> String? {
        guard let prefs = SCPreferencesCreate(nil, "Switchback" as CFString, nil),
              let current = SCNetworkSetCopyCurrent(prefs) else { return nil }
        return SCNetworkSetGetSetID(current) as String?
    }
}
#endif
