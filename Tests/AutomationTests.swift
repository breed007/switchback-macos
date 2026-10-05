import XCTest

/// AutomationSwitch's rules for Shortcuts and Focus (docs/v0.5-spec.md, F6 and F7),
/// with fakes for every backend.
final class AutomationTests: XCTestCase {
    private var routed: [String] = []
    private var helper: [String] = []
    private var announced: [AutomationSwitch.Announcement] = []

    override func setUp() {
        routed = []; helper = []; announced = []
    }

    private func automation(current: String? = "auto", helperEnabled: Bool = true,
                            routedError: Error? = nil, helperError: Error? = nil) -> AutomationSwitch {
        AutomationSwitch(
            currentID: { current },
            helperEnabled: { helperEnabled },
            routedSwitch: { id in self.routed.append(id); if let routedError { throw routedError } },
            helperSwitch: { id in self.helper.append(id); if let helperError { throw helperError } },
            announce: { self.announced.append($0) })
    }

    // MARK: - Already there

    func testAlreadyCurrentDoesNothingForEitherSource() async throws {
        for source in [AutomationSwitch.Source.shortcut, .focus] {
            let outcome = try await automation(current: "office").run(id: "office", name: "Office", source: source)
            XCTAssertEqual(outcome, .alreadyCurrent)
        }
        XCTAssertEqual(routed + helper, [])
        XCTAssertEqual(announced, [], "no notification when nothing changed")
    }

    // MARK: - Shortcuts

    func testShortcutSwitchesThroughTheRouterAndAnnounces() async throws {
        let outcome = try await automation().run(id: "office", name: "Office", source: .shortcut)
        XCTAssertEqual(outcome, .switched)
        XCTAssertEqual(routed, ["office"])
        XCTAssertEqual(helper, [], "the router decides helper vs. prompt for a shortcut")
        XCTAssertEqual(announced, [.switched(name: "Office", source: .shortcut)])
    }

    func testShortcutWithoutTheHelperStillUsesTheRouter() async throws {
        // The router falls back to the admin prompt; someone ran the shortcut and can answer.
        _ = try await automation(helperEnabled: false).run(id: "office", name: "Office", source: .shortcut)
        XCTAssertEqual(routed, ["office"])
    }

    func testShortcutFailureThrowsAndAnnouncesNothing() async {
        do {
            _ = try await automation(routedError: LocationSwitcherError.canceled)
                .run(id: "office", name: "Office", source: .shortcut)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(announced, [])
        }
    }

    // MARK: - Focus

    func testFocusSwitchesThroughTheHelperOnlyAndAnnounces() async throws {
        let outcome = try await automation().run(id: "office", name: "Office", source: .focus)
        XCTAssertEqual(outcome, .switched)
        XCTAssertEqual(helper, ["office"])
        XCTAssertEqual(routed, [], "a Focus must never reach the admin prompt")
        XCTAssertEqual(announced, [.switched(name: "Office", source: .focus)])
    }

    func testFocusWithoutTheHelperSkipsAndSaysHowToFixIt() async throws {
        let outcome = try await automation(helperEnabled: false).run(id: "office", name: "Office", source: .focus)
        XCTAssertEqual(outcome, .needsHelper)
        XCTAssertEqual(routed + helper, [])
        XCTAssertEqual(announced, [.helperNeeded])
    }

    func testFocusRefusedByPolicyIsAnnouncedNotPrompted() async throws {
        let refused = HelperError.helperReported(HelperConstants.ErrorCode.policyDenied)
        let outcome = try await automation(helperError: refused).run(id: "office", name: "Office", source: .focus)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(routed, [], "no fallback to the prompt for a Focus")
        XCTAssertEqual(announced, [.focusFailed(name: "Office")])
    }

    // MARK: - Matching and wording

    func testLocationSearchIgnoresCaseWidthAndInvisibles() {
        XCTAssertTrue(LocationSearch.matches("Office", query: "office"))
        XCTAssertTrue(LocationSearch.matches("Client A", query: "client"))
        XCTAssertTrue(LocationSearch.matches("Office", query: "\u{FF2F}ff"))     // full-width O
        XCTAssertTrue(LocationSearch.matches("Office", query: ""))              // empty query lists all
        XCTAssertFalse(LocationSearch.matches("Office", query: "home"))
    }

    func testNotificationWording() {
        XCTAssertEqual(SwitchNotifier.text(for: .switched(name: "Office", source: .focus)).0, "Switched to Office")
        XCTAssertEqual(SwitchNotifier.text(for: .switched(name: "Office", source: .focus)).1,
                       "Your Focus changed your network location.")
        XCTAssertEqual(SwitchNotifier.text(for: .switched(name: "Office", source: .shortcut)).1,
                       "A shortcut changed your network location.")
        XCTAssertTrue(SwitchNotifier.text(for: .helperNeeded).1.contains("Set Up Passwordless Switching"))
        XCTAssertEqual(SwitchNotifier.text(for: .focusFailed(name: "Office")).0, "Couldn\u{2019}t switch to Office")
    }
}
