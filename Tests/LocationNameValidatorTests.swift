import XCTest

/// F3 acceptance tests (docs/v0.5-spec.md). The validator source is compiled
/// straight into this bundle, so the tests need no host app and no privileges.
final class LocationNameValidatorTests: XCTestCase {
    typealias V = LocationNameValidator

    private let office = V.Existing(id: "set-office", name: "Office")
    private let cafe = V.Existing(id: "set-cafe", name: "Caf\u{00E9}")       // NFC "Café"
    private let automatic = V.Existing(id: "set-auto", name: "Automatic")

    // MARK: - Stored name

    func testFamilyEmojiSurvivesIntact() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Home"
        XCTAssertEqual(V.clean(family), family)
        XCTAssertEqual(V.clean(family).count, 6)   // one family glyph, a space, "Home"
    }

    func testZeroWidthSpaceIsRemovedNotTurnedIntoASpace() {
        XCTAssertEqual(V.clean("Off\u{200B}ice"), "Office")
    }

    func testByteOrderMarkFromAPasteIsRemoved() {
        XCTAssertEqual(V.clean("\u{FEFF}Office"), "Office")
    }

    func testMultiLinePasteBecomesOneLine() {
        XCTAssertEqual(V.clean("Client A\nOffice 3\r\n\tFloor 2"), "Client A Office 3 Floor 2")
    }

    func testNoBreakAndRepeatedSpacesCollapse() {
        XCTAssertEqual(V.clean("  Client\u{00A0}\u{00A0} A  "), "Client A")
    }

    func testStoredNameIsNFC() {
        let stored = V.clean("Cafe\u{0301}")                 // decomposed é
        XCTAssertEqual(stored.unicodeScalars.count, 4)       // C a f é
        XCTAssertEqual(stored, "Caf\u{00E9}")
    }

    // MARK: - Problems

    func testEmptyAndInvisibleOnlyNamesAreEmpty() {
        for raw in ["", "   ", "\n\t", "\u{200B}", "\u{200D}\u{FEFF} "] {
            XCTAssertEqual(V.validate(raw, existing: []).problem, .empty, "raw: \(raw.debugDescription)")
        }
    }

    func testLengthLimitIs128Characters() {
        XCTAssertTrue(V.validate(String(repeating: "a", count: 128), existing: []).isValid)
        XCTAssertEqual(V.validate(String(repeating: "a", count: 129), existing: []).problem, .tooLong)
    }

    func testAutomaticIsReservedInAnyCase() {
        for raw in ["Automatic", "automatic", " AUTOMATIC ", "Ａｕｔｏｍａｔｉｃ"] {
            XCTAssertEqual(V.validate(raw, existing: [office]).problem, .reserved, "raw: \(raw)")
        }
        XCTAssertTrue(V.isReserved("automatic"))
    }

    func testFullWidthLookalikeIsADuplicate() {
        XCTAssertEqual(V.validate("\u{FF2F}ffice", existing: [office]).problem, .duplicate(of: "Office"))
    }

    func testCaseOnlyVariantIsADuplicate() {
        XCTAssertEqual(V.validate("OFFICE", existing: [office]).problem, .duplicate(of: "Office"))
    }

    func testInvisibleJoinerCantDisguiseADuplicate() {
        XCTAssertEqual(V.validate("Off\u{200D}ice", existing: [office]).problem, .duplicate(of: "Office"))
    }

    func testNFCAndNFDCafeAreDuplicates() {
        XCTAssertEqual(V.validate("Cafe\u{0301}", existing: [cafe]).problem, .duplicate(of: "Caf\u{00E9}"))
    }

    func testAccentsStaySignificant() {
        let resume = V.Existing(id: "set-resume", name: "Resume")
        XCTAssertTrue(V.validate("R\u{00E9}sum\u{00E9}", existing: [resume]).isValid)
    }

    // MARK: - Renaming

    func testCaseOnlyRenameOfTheSameLocationIsAllowed() {
        let lower = V.Existing(id: "set-1", name: "office")
        XCTAssertTrue(V.validate("Office", existing: [lower], excludingID: "set-1").isValid)
    }

    func testRenamingOntoAnotherLocationsNameIsADuplicate() {
        let home = V.Existing(id: "set-home", name: "Home")
        XCTAssertEqual(V.validate("office", existing: [office, home], excludingID: "set-home").problem,
                       .duplicate(of: "Office"))
    }

    // MARK: - Lookalike warnings (warn, never block)

    func testCyrillicLookalikeWarnsAndNamesTheMatch() {
        let result = V.validate("\u{041E}ffice", existing: [office])   // Cyrillic capital O
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.warning, .lookalike(of: "Office", script: "Cyrillic"))
    }

    func testMixedScriptWithoutAMatchStillWarns() {
        let result = V.validate("W\u{043E}rk", existing: [office])     // Cyrillic small o
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.warning, .mixedScript(script: "Cyrillic"))
    }

    func testGreekLookalikeIsDetected() {
        let result = V.validate("\u{039F}ffice", existing: [office])   // Greek capital Omicron
        XCTAssertEqual(result.warning, .lookalike(of: "Office", script: "Greek"))
    }

    func testSingleScriptNamesDontWarn() {
        XCTAssertNil(V.validate("\u{041C}\u{043E}\u{0441}\u{043A}\u{0432}\u{0430}", existing: [office]).warning) // "Москва"
        XCTAssertNil(V.validate("Client A", existing: [office]).warning)
        XCTAssertNil(V.validate("\u{1F3E0} Home", existing: [office]).warning)
    }

    func testOrdinaryNameIsValidWithNoWarning() {
        let result = V.validate("Client B", existing: [office, cafe, automatic])
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.name, "Client B")
    }
}
