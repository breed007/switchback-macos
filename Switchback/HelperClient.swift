import Foundation
import ServiceManagement
import XPC

/// The app's side of SwitchbackHelper: registration through `SMAppService`, and
/// the one XPC call.
enum HelperClient {
    private static var service: SMAppService {
        SMAppService.daemon(plistName: HelperConstants.plistName)
    }

    static var status: SMAppService.Status { service.status }

    /// True when the helper is registered and approved, so switches need no password.
    static var isEnabled: Bool { status == .enabled }

    /// Register the helper. On an unmanaged Mac this leaves it in
    /// `.requiresApproval` until someone approves it in System Settings.
    ///
    /// Gotcha (found in the milestone 1 spike, macOS 27): for a daemon,
    /// `register()` throws "Operation not permitted" even when registration
    /// succeeded and is only awaiting approval. Treat that as success.
    static func register() throws {
        guard status != .enabled else { return }
        do {
            try service.register()
        } catch {
            if status == .requiresApproval { return }
            throw error
        }
    }

    static func unregister() throws {
        if status != .notRegistered { try service.unregister() }
    }

    /// Opens System Settings → General → Login Items & Extensions.
    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Ask the helper to make `setID` the current location. Blocks until the
    /// helper replies, so call it off the main thread.
    static func switchTo(setID: String) throws {
        let conn = xpc_connection_create_mach_service(HelperConstants.machServiceName, nil, 0)
        _ = xpc_connection_set_peer_code_signing_requirement(conn, HelperConstants.helperRequirement)
        xpc_connection_set_event_handler(conn) { _ in }   // required before resume
        xpc_connection_resume(conn)
        defer { xpc_connection_cancel(conn) }

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, HelperConstants.Key.op, HelperConstants.opSwitchTo)
        xpc_dictionary_set_string(message, HelperConstants.Key.setID, setID)
        let reply = xpc_connection_send_message_with_reply_sync(conn, message)

        if xpc_get_type(reply) == XPC_TYPE_ERROR {
            let why = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION)
                .map { String(cString: $0) } ?? "connection error"
            throw HelperError.communicationFailed(why)
        }
        guard xpc_dictionary_get_bool(reply, HelperConstants.Key.ok) else {
            let code = xpc_dictionary_get_string(reply, HelperConstants.Key.error)
                .map { String(cString: $0) } ?? "unknown"
            throw HelperError.helperReported(code)
        }
    }
}

enum HelperError: Error, CustomStringConvertible {
    case communicationFailed(String)
    case helperReported(String)

    var description: String {
        switch self {
        case .communicationFailed(let why): return "Couldn\u{2019}t reach Switchback\u{2019}s helper (\(why))."
        case .helperReported(let code):     return "Switchback\u{2019}s helper couldn\u{2019}t switch (\(code))."
        }
    }
}

extension SMAppService.Status {
    var label: String {
        switch self {
        case .notRegistered:    return "notRegistered"
        case .enabled:          return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound:         return "notFound"
        @unknown default:       return "unknown(\(rawValue))"
        }
    }
}
