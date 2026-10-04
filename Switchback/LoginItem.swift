import ServiceManagement

/// Launch at Login, through `SMAppService.mainApp`. Ported from Crossbar.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// True when the user must approve Switchback under System Settings → General →
    /// Login Items & Extensions before it will launch at login.
    static var requiresApproval: Bool { status == .requiresApproval }

    /// Turn launch-at-login on or off. Throws if the system rejects the change.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if status == .enabled || status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
