import Foundation
import SystemConfiguration
import XPC
import os

// SwitchbackHelper: the privileged (root) daemon. Its whole job is to make an
// existing network location current, by set ID, for the signed Switchback app.
// It has no create, rename, delete, or edit operation and must never gain one.
// That limit is what makes passwordless switching safe to offer to standard users.
//
// Security model (ported from Crossbar's Backend B):
//   1. Every peer is pinned to `HelperConstants.clientRequirement`; the OS drops
//      messages from anything that isn't Switchback signed by our team.
//   2. The client's set ID is re-validated against live config before any write.

private let log = Logger(subsystem: HelperConstants.helperBundleID, category: "switch")

/// All work runs on one serial queue, so two callers can't race a commit.
private let workQueue = DispatchQueue(label: "com.breed007.switchback.helper.work")

/// launchd starts the helper on demand; exit after a quiet minute instead of
/// holding a root process open. The next message relaunches it.
private var idleExit: DispatchWorkItem?
private func scheduleIdleExit() {
    idleExit?.cancel()
    let item = DispatchWorkItem { exit(0) }
    idleExit = item
    workQueue.asyncAfter(deadline: .now() + 60, execute: item)
}

/// Make `setID` the current location. Returns nil on success or an error code.
private func switchTo(setID: String) -> String? {
    guard let prefs = SCPreferencesCreate(nil, HelperConstants.helperBundleID as CFString, nil) else {
        return "open-prefs-failed"
    }
    let sets = (SCNetworkSetCopyAll(prefs) as? [SCNetworkSet]) ?? []
    guard let target = sets.first(where: { (SCNetworkSetGetSetID($0) as String?) == setID }) else {
        return "unknown-set"
    }
    guard SCNetworkSetSetCurrent(target) else { return "commit-failed" }
    guard SCPreferencesCommitChanges(prefs) else { return "commit-failed" }
    guard SCPreferencesApplyChanges(prefs) else { return "apply-failed" }
    return nil
}

/// The current set ID, for the audit log.
private func currentSetID() -> String {
    guard let prefs = SCPreferencesCreate(nil, HelperConstants.helperBundleID as CFString, nil),
          let current = SCNetworkSetCopyCurrent(prefs),
          let id = SCNetworkSetGetSetID(current) as String? else { return "none" }
    return id
}

private func handle(_ message: xpc_object_t, from peer: xpc_connection_t) {
    guard let reply = xpc_dictionary_create_reply(message) else { return }
    let uid = xpc_connection_get_euid(peer)

    func send(_ error: String?) {
        xpc_dictionary_set_bool(reply, HelperConstants.Key.ok, error == nil)
        if let error { xpc_dictionary_set_string(reply, HelperConstants.Key.error, error) }
        xpc_connection_send_message(peer, reply)
    }

    guard let op = xpc_dictionary_get_string(message, HelperConstants.Key.op).map({ String(cString: $0) }),
          op == HelperConstants.opSwitchTo else {
        log.error("uid \(uid, privacy: .public): rejected unknown op")
        return send("unknown-op")
    }
    guard let setID = xpc_dictionary_get_string(message, HelperConstants.Key.setID).map({ String(cString: $0) }) else {
        return send("unknown-set")
    }

    // Set IDs are opaque GUIDs and logged in the clear; location names (which can
    // name clients) are never logged.
    let fromID = currentSetID()
    let result = switchTo(setID: setID)
    log.notice("uid \(uid, privacy: .public) switch \(fromID, privacy: .public) -> \(setID, privacy: .public): \(result ?? "ok", privacy: .public)")
    send(result)
}

// MARK: - Listener

let listener = xpc_connection_create_mach_service(
    HelperConstants.machServiceName, workQueue,
    UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))

xpc_connection_set_event_handler(listener) { peer in
    guard xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }

    // Pin the caller. The OS enforces this per message; anything failing the
    // requirement never reaches `handle`.
    _ = xpc_connection_set_peer_code_signing_requirement(peer, HelperConstants.clientRequirement)
    xpc_connection_set_target_queue(peer, workQueue)

    xpc_connection_set_event_handler(peer) { event in
        guard xpc_get_type(event) != XPC_TYPE_ERROR else { return }
        handle(event, from: peer)
        scheduleIdleExit()
    }
    xpc_connection_resume(peer)
}
xpc_connection_resume(listener)
workQueue.async { scheduleIdleExit() }
dispatchMain()
