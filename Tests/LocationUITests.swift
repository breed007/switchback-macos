import XCTest

/// The pure logic behind milestone 4's UI (docs/v0.5-spec.md, F4–F6, F8): custom
/// ordering, rename/delete rules, the name-field feedback line, and the details line.
final class LocationUITests: XCTestCase {

    private func loc(_ id: String, _ name: String, current: Bool = false) -> NetworkLocation {
        NetworkLocation(id: id, name: name, isCurrent: current)
    }

    private lazy var office = loc("o", "Office", current: true)
    private lazy var home = loc("h", "Home")
    private lazy var client = loc("c", "client a")
    private lazy var automatic = loc("a", "Automatic")

    // MARK: - Ordering (F5, F8)

    func testEmptyOrderIsAlphabetical() {
        XCTAssertEqual(LocationOrder.apply([], to: [office, home, client, automatic]).map(\.name),
                       ["Automatic", "client a", "Home", "Office"])
    }

    func testSavedOrderComesFirstThenNewOnesAlphabetically() {
        let result = LocationOrder.apply(["o", "a"], to: [home, office, client, automatic])
        XCTAssertEqual(result.map(\.name), ["Office", "Automatic", "client a", "Home"])
    }

    func testDeletedAndDuplicatedIDsInTheSavedOrderAreHarmless() {
        let result = LocationOrder.apply(["gone", "h", "o", "h"], to: [office, home])
        XCTAssertEqual(result.map(\.name), ["Home", "Office"])
    }

    func testMovingDownAndUp() {
        let shown = [automatic, client, home, office]   // a c h o
        XCTAssertEqual(LocationOrder.moving(shown, from: 0, to: 3), ["c", "h", "a", "o"])   // before "o"
        XCTAssertEqual(LocationOrder.moving(shown, from: 0, to: 4), ["c", "h", "o", "a"])   // to the end
        XCTAssertEqual(LocationOrder.moving(shown, from: 3, to: 0), ["o", "a", "c", "h"])
        XCTAssertEqual(LocationOrder.moving(shown, from: 1, to: 1), ["a", "c", "h", "o"])   // dropped in place
        XCTAssertEqual(LocationOrder.moving(shown, from: 9, to: 0), ["a", "c", "h", "o"])   // out of range: no change
    }

    func testOrderPersistsInDefaults() throws {
        let suite = "LocationUITests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let order = LocationOrder(defaults: defaults)
        XCTAssertEqual(order.ids, [])
        order.save(["o", "h"])
        XCTAssertEqual(LocationOrder(defaults: defaults).ids, ["o", "h"])
    }

    // MARK: - Rename and delete rules (F5)

    func testProtectedLocationCantBeRenamedOrDeleted() {
        XCTAssertNotNil(LocationRules.renameBlockReason(for: automatic))
        XCTAssertNotNil(LocationRules.deleteBlockReason(for: automatic, among: [automatic, office]))
        XCTAssertNil(LocationRules.renameBlockReason(for: home))
    }

    func testCurrentAndOnlyLocationsCantBeDeleted() {
        XCTAssertEqual(LocationRules.deleteBlockReason(for: office, among: [office, home]),
                       "Switch to another location before deleting this one.")
        let only = loc("x", "Solo", current: true)
        XCTAssertEqual(LocationRules.deleteBlockReason(for: only, among: [only]),
                       "You can\u{2019}t delete your only location.")
        XCTAssertNil(LocationRules.deleteBlockReason(for: home, among: [office, home]))
    }

    // MARK: - Name-field feedback (F4)

    private func feedback(_ raw: String, excluding: String? = nil) -> NameFeedback? {
        let existing = [office, home, automatic].map { LocationNameValidator.Existing(id: $0.id, name: $0.name) }
        return LocationNameValidator.validate(raw, existing: existing, excludingID: excluding).feedback
    }

    func testEmptyBlocksSilently() {
        XCTAssertEqual(feedback("  "), NameFeedback(text: "", blocksConfirm: true))
    }

    func testDuplicateNamesTheClash() {
        XCTAssertEqual(feedback("OFFICE"), NameFeedback(text: "\u{201C}Office\u{201D} already uses that name.", blocksConfirm: true))
    }

    func testReservedAndTooLongBlock() {
        XCTAssertEqual(feedback("automatic")?.blocksConfirm, true)
        XCTAssertEqual(feedback(String(repeating: "x", count: 129))?.blocksConfirm, true)
    }

    func testLookalikeWarnsWithoutBlocking() {
        XCTAssertEqual(feedback("H\u{043E}me"),     // Cyrillic о
                       NameFeedback(text: "Looks like \u{201C}Home\u{201D} but uses Cyrillic letters.", blocksConfirm: false))
    }

    func testValidNameHasNoFeedbackIncludingRenameToItself() {
        XCTAssertNil(feedback("Client B"))
        XCTAssertNil(feedback("home", excluding: "h"))
    }

    // MARK: - Details line (F6)

    func testDetailsSummary() {
        XCTAssertEqual(NetworkDetails(service: "Wi-Fi", address: "10.0.4.22", dns: ["10.0.0.1", "1.1.1.1", "8.8.8.8"]).summary,
                       "Wi-Fi \u{00B7} 10.0.4.22 \u{00B7} DNS 10.0.0.1, 1.1.1.1")
        XCTAssertEqual(NetworkDetails(service: "Ethernet", address: "192.168.1.5").summary,
                       "Ethernet \u{00B7} 192.168.1.5")
        XCTAssertEqual(NetworkDetails().summary, "Not connected")
        XCTAssertEqual(NetworkDetails(dns: ["10.0.0.1"]).summary, "Not connected")
    }
}
