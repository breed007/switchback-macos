import XCTest

/// The helper refuses malformed set IDs before touching preferences or logging.
final class HelperInputTests: XCTestCase {
    func testRealSetIDsAreWellFormed() {
        XCTAssertTrue(HelperConstants.isWellFormedSetID("82E3EBFA-2ED3-4688-A70F-E52731906800"))
        XCTAssertTrue(HelperConstants.isWellFormedSetID("00000000-0000-0000-0000-000000000000"))
    }

    func testMalformedSetIDsAreRefused() {
        for bad in ["", "sets\n82E3EBFA-2ED3-4688-A70F-E52731906800", "a b", "../etc", "id;rm",
                    "6F8FF969\u{0000}", "\u{202E}6F8F", String(repeating: "A", count: 65)] {
            XCTAssertFalse(HelperConstants.isWellFormedSetID(bad), bad.debugDescription)
        }
    }
}
