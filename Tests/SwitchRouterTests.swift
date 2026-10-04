import XCTest

/// SwitchRouter's rules (docs/v0.5-spec.md, F1): which backend runs, and which
/// helper failures fall back to the admin prompt. Fakes stand in for the helper
/// and the admin-prompt backend, so no privileges are involved.
final class SwitchRouterTests: XCTestCase {

    /// Records calls instead of touching the system. Optionally fails switches.
    private final class FakeAuthorized: LocationSwitcher {
        var calls: [String] = []
        var switchError: Error?
        func switchTo(locationID: String) async throws {
            calls.append("switch \(locationID)")
            if let switchError { throw switchError }
        }
        func createLocation(named name: String) async throws -> String { calls.append("create \(name)"); return "new-id" }
        func renameLocation(locationID: String, to name: String) async throws { calls.append("rename \(locationID) \(name)") }
        func deleteLocation(locationID: String) async throws { calls.append("delete \(locationID)") }
    }

    private var authorized: FakeAuthorized!
    private var helperCalls: [String] = []

    override func setUp() {
        authorized = FakeAuthorized()
        helperCalls = []
    }

    private func router(helperEnabled: Bool, helperError: Error? = nil) -> SwitchRouter {
        SwitchRouter(authorized: authorized,
                     helperEnabled: { helperEnabled },
                     helperSwitch: { id in
                         self.helperCalls.append(id)
                         if let helperError { throw helperError }
                     })
    }

    // MARK: - Which backend switches

    func testHelperDisabledUsesTheAdminPrompt() async throws {
        try await router(helperEnabled: false).switchTo(locationID: "office")
        XCTAssertEqual(helperCalls, [])
        XCTAssertEqual(authorized.calls, ["switch office"])
    }

    func testHelperEnabledSwitchesWithoutThePrompt() async throws {
        try await router(helperEnabled: true).switchTo(locationID: "office")
        XCTAssertEqual(helperCalls, ["office"])
        XCTAssertEqual(authorized.calls, [])
    }

    // MARK: - Fallback

    func testUnreachableHelperFallsBackToThePrompt() async throws {
        try await router(helperEnabled: true, helperError: HelperError.communicationFailed("Connection invalid"))
            .switchTo(locationID: "office")
        XCTAssertEqual(helperCalls, ["office"])
        XCTAssertEqual(authorized.calls, ["switch office"])
    }

    func testPolicyDeniedFallsBackToThePrompt() async throws {
        try await router(helperEnabled: true,
                         helperError: HelperError.helperReported(HelperConstants.ErrorCode.policyDenied))
            .switchTo(locationID: "office")
        XCTAssertEqual(authorized.calls, ["switch office"])
    }

    func testOlderHelperWithoutTheOpFallsBack() async throws {
        try await router(helperEnabled: true,
                         helperError: HelperError.helperReported(HelperConstants.ErrorCode.unknownOp))
            .switchTo(locationID: "office")
        XCTAssertEqual(authorized.calls, ["switch office"])
    }

    func testUnknownLocationIsReportedNotRetried() async {
        await assertThrowsHelperError(code: HelperConstants.ErrorCode.unknownSet)
        XCTAssertEqual(authorized.calls, [], "an unknown location would fail the same way via the prompt")
    }

    func testFailedCommitIsReportedNotRetried() async {
        await assertThrowsHelperError(code: HelperConstants.ErrorCode.commitFailed)
        XCTAssertEqual(authorized.calls, [])
    }

    func testCancelingTheFallbackPromptStaysACancel() async {
        authorized.switchError = LocationSwitcherError.canceled
        do {
            try await router(helperEnabled: true, helperError: HelperError.communicationFailed("gone"))
                .switchTo(locationID: "office")
            XCTFail("expected .canceled")
        } catch LocationSwitcherError.canceled {
            // The controller treats this as a silent no-op.
        } catch {
            XCTFail("expected .canceled, got \(error)")
        }
    }

    // MARK: - Management never goes through the helper

    func testCreateRenameDeleteAlwaysUseTheAdminPrompt() async throws {
        let r = router(helperEnabled: true)
        let id = try await r.createLocation(named: "Client A")
        try await r.renameLocation(locationID: "set-1", to: "Client B")
        try await r.deleteLocation(locationID: "set-1")
        XCTAssertEqual(id, "new-id")
        XCTAssertEqual(helperCalls, [])
        XCTAssertEqual(authorized.calls, ["create Client A", "rename set-1 Client B", "delete set-1"])
    }

    // MARK: - The fallback rule itself

    func testAllowsFallbackTable() {
        XCTAssertTrue(HelperError.communicationFailed("x").allowsFallback)
        XCTAssertTrue(HelperError.helperReported(HelperConstants.ErrorCode.policyDenied).allowsFallback)
        XCTAssertTrue(HelperError.helperReported(HelperConstants.ErrorCode.unknownOp).allowsFallback)
        for code in [HelperConstants.ErrorCode.unknownSet, HelperConstants.ErrorCode.commitFailed,
                     HelperConstants.ErrorCode.applyFailed, HelperConstants.ErrorCode.openPrefsFailed, "something-new"] {
            XCTAssertFalse(HelperError.helperReported(code).allowsFallback, code)
        }
    }

    private func assertThrowsHelperError(code: String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await router(helperEnabled: true, helperError: HelperError.helperReported(code))
                .switchTo(locationID: "office")
            XCTFail("expected \(code)", file: file, line: line)
        } catch let error as HelperError {
            XCTAssertEqual(error, .helperReported(code), file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}
