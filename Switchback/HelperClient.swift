import Foundation
import ServiceManagement
@preconcurrency import XPC

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

    /// Ask the helper to make `setID` the current location.
    static func switchTo(setID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let conn = xpc_connection_create_mach_service(HelperConstants.machServiceName, nil, 0)
            _ = xpc_connection_set_peer_code_signing_requirement(conn, HelperConstants.helperRequirement)
            xpc_connection_set_event_handler(conn) { _ in }   // required before resume
            xpc_connection_resume(conn)

            let message = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(message, HelperConstants.Key.op, HelperConstants.opSwitchTo)
            xpc_dictionary_set_string(message, HelperConstants.Key.setID, setID)

            xpc_connection_send_message_with_reply(conn, message, DispatchQueue.global()) { reply in
                defer { xpc_connection_cancel(conn) }
                if xpc_get_type(reply) == XPC_TYPE_ERROR {
                    let why = xpc_dictionary_get_string(reply, XPC_ERROR_KEY_DESCRIPTION)
                        .map { String(cString: $0) } ?? "connection error"
                    continuation.resume(throwing: HelperError.communicationFailed(why))
                } else if xpc_dictionary_get_bool(reply, HelperConstants.Key.ok) {
                    continuation.resume()
                } else {
                    let code = xpc_dictionary_get_string(reply, HelperConstants.Key.error)
                        .map { String(cString: $0) } ?? "unknown"
                    continuation.resume(throwing: HelperError.helperReported(code))
                }
            }
        }
    }
}

enum HelperError: Error, Equatable, CustomStringConvertible {
    case communicationFailed(String)
    case helperReported(String)

    /// Whether the switch should be retried through the admin prompt. Yes when the
    /// helper can't be reached, refuses by policy, or is too old to know the op.
    /// No when the helper ran and the switch itself failed: an unknown location or
    /// a failed commit would fail the same way through the prompt.
    var allowsFallback: Bool {
        switch self {
        case .communicationFailed:
            return true
        case .helperReported(let code):
            return code == HelperConstants.ErrorCode.policyDenied
                || code == HelperConstants.ErrorCode.unknownOp
        }
    }

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
