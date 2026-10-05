#if DEBUG
import AppKit
import SystemConfiguration

/// Debug-only command-line hooks for exercising the helper from Terminal. They run
/// inside the signed Switchback binary, which is the only caller the helper
/// accepts, so `/Applications/Switchback.app/Contents/MacOS/Switchback <flag>`
/// tests the real path.
///
///   --helper-status            print the SMAppService status
///   --helper-register          register the helper (then approve in System Settings)
///   --helper-unregister        remove it
///   --helper-switch <setID>    switch through the helper only
///   --helper-selftest          no-op switch to the current set, then an unknown set
///   --switch <setID>           switch through SwitchRouter (helper, else admin prompt)
///   --policy                   print the managed policy and whether you're an admin
///   --login-item [on|off]      print, or set, Launch at Login
///   --details                  print the menu's live details line and its parts
///   --locations                print locations in menu order, with service info
///   --menu                     print the real menu as it would open
///   --manage                   print the Manage Locations window's rows
///   --manage-sample            the same, with made-up locations covering every row kind
///   --demo menu|manage|dialog [light|dark]
///                              open that UI with sample data and keep running, for
///                              README screenshots (scripts/screenshots.sh)
enum DebugCommands {
    /// Returns an exit code if a debug flag was handled, or nil to launch normally.
    static func run(_ args: [String]) -> Int32? {
        guard args.count >= 2, args[1].hasPrefix("--") else { return nil }

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
            return attempt("helper switch to \(args[2])") {
                try blocking { try await HelperClient.switchTo(setID: args[2]) }
            }

        case "--switch":
            guard args.count >= 3 else { print("usage: --switch <setID>"); return 64 }
            return attempt("routed switch to \(args[2])") {
                try blocking { try await SwitchRouter().switchTo(locationID: args[2]) }
            }

        case "--helper-selftest":
            return selfTest()

        case "--policy":
            let requireAdmin = HelperPolicy.requireAdminToSwitch()
            let admin = HelperPolicy.isAdmin(uid: getuid())
            print("RequireAdminToSwitch: \(requireAdmin) (\(HelperPolicy.managedPreferencesPath))")
            print("uid \(getuid()) is admin: \(admin)")
            print("helper would \(HelperPolicy.allows(requireAdmin: requireAdmin, callerIsAdmin: admin) ? "allow" : "refuse") a switch from this user")
            return 0

        case "--details":
            let details = NetworkDetails.current()
            print("summary: \(details.summary)")
            print("service: \(details.service ?? "-")  address: \(details.address ?? "-")  dns: \(details.dns)")
            return 0

        case "--locations":
            let monitor = StatusMonitor()
            for (index, loc) in LocationOrder.apply(LocationOrder().ids, to: monitor.locations).enumerated() {
                print("\(index + 1). \(loc.isCurrent ? "*" : " ") \(loc.name)  [\(loc.id)]  services: \(loc.serviceCount)  primary: \(loc.primaryService ?? "-")")
            }
            return 0

        case "--demo":
            DemoData.active = true
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            if args.count >= 4 { app.appearance = NSAppearance(named: args[3] == "light" ? .aqua : .darkAqua) }
            let controller = StatusItemController()
            let what = args.count >= 3 ? args[2] : "menu"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.debugDemo(what) }
            app.run()   // until killed
            return 0

        case "--menu":
            _ = NSApplication.shared
            StatusItemController().debugMenuDump().forEach { print($0) }
            return 0

        case "--manage", "--manage-sample":
            _ = NSApplication.shared
            StatusItemController().debugManageDump(sample: args[1] == "--manage-sample").forEach { print($0) }
            return 0

        case "--login-item":
            if args.count >= 3 {
                let on = args[2] == "on"
                guard attempt(on ? "enable launch at login" : "disable launch at login",
                              { try LoginItem.setEnabled(on) }) == 0 else { return 1 }
            }
            print("launch at login: \(LoginItem.status.label)")
            return 0

        default:
            return nil   // not ours; launch normally
        }
    }

    private static func selfTest() -> Int32 {
        guard let current = currentSetID() else { print("FAIL: can't read current set"); return 1 }
        let noOp = attempt("no-op switch to current set \(current)") {
            try blocking { try await HelperClient.switchTo(setID: current) }
        }
        var unknownOK = false
        do {
            try blocking { try await HelperClient.switchTo(setID: "00000000-0000-0000-0000-000000000000") }
            print("FAIL: unknown set was accepted")
        } catch HelperError.helperReported(let code) where code == HelperConstants.ErrorCode.unknownSet {
            print("ok: unknown set rejected with \(code)")
            unknownOK = true
        } catch {
            print("FAIL: unknown set: \(error)")
        }
        return (noOp == 0 && unknownOK) ? 0 : 1
    }

    private static func attempt(_ label: String, _ work: () throws -> Void) -> Int32 {
        do {
            try work()
            print("ok: \(label) (helper \(HelperClient.status.label))")
            return 0
        } catch {
            print("FAIL: \(label): \(error) (helper \(HelperClient.status.label))")
            return 1
        }
    }

    /// Run async work to completion from this synchronous, pre-AppKit context.
    private static func blocking(_ work: @escaping () async throws -> Void) throws {
        final class Box: @unchecked Sendable { var error: Error? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { try await work() } catch { box.error = error }
            done.signal()
        }
        done.wait()
        if let error = box.error { throw error }
    }

    private static func currentSetID() -> String? {
        guard let prefs = SCPreferencesCreate(nil, "Switchback" as CFString, nil),
              let current = SCNetworkSetCopyCurrent(prefs) else { return nil }
        return SCNetworkSetGetSetID(current) as String?
    }
}
#endif
