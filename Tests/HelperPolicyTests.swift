import XCTest

/// The RequireAdminToSwitch policy (docs/v0.5-spec.md, F1). Parsing uses temp files
/// (with the root-owner check off, except where it's the thing under test); admin
/// detection is checked against real accounts on this Mac.
final class HelperPolicyTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func plist(_ dict: [String: Any]) throws -> String {
        let url = dir.appendingPathComponent("com.breed007.switchback.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
        return url.path
    }

    // MARK: - Reading the managed preference

    func testTrueRequiresAdmin() throws {
        XCTAssertTrue(HelperPolicy.requireAdminToSwitch(plistPath: try plist([HelperPolicy.requireAdminKey: true]),
                                                        requireRootOwner: false))
    }

    func testFalseMissingKeyOrMissingFileMeansAnyoneCanSwitch() throws {
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch(plistPath: try plist([HelperPolicy.requireAdminKey: false]),
                                                         requireRootOwner: false))
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch(plistPath: try plist(["SomethingElse": true]),
                                                         requireRootOwner: false))
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch(plistPath: dir.appendingPathComponent("none.plist").path,
                                                         requireRootOwner: false))
    }

    func testOnlyARealBoolCounts() throws {
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch(plistPath: try plist([HelperPolicy.requireAdminKey: "YES"]),
                                                         requireRootOwner: false))
    }

    func testGarbageFileIsIgnored() throws {
        let url = dir.appendingPathComponent("garbage.plist")
        try Data("not a plist".utf8).write(to: url)
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch(plistPath: url.path, requireRootOwner: false))
    }

    func testAFileNotOwnedByRootIsIgnored() throws {
        // A temp file belongs to the test user, so with the real (root-owner)
        // check on, even "true" must not count.
        let path = try plist([HelperPolicy.requireAdminKey: true])
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch(plistPath: path))
    }

    func testTheRealManagedPathIsUnsetOnThisMac() {
        // No MDM profile sets the key here, so the default applies.
        XCTAssertFalse(HelperPolicy.requireAdminToSwitch())
    }

    // MARK: - Admin detection

    func testAdminDetectionMatchesTheSystem() throws {
        let id = Process()
        id.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        id.arguments = ["-Gn"]
        let pipe = Pipe()
        id.standardOutput = pipe
        try id.run()
        id.waitUntilExit()
        let groups = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(HelperPolicy.isAdmin(uid: getuid()), groups.contains("admin"))
    }

    func testRootIsAdminAndNobodyIsNot() throws {
        XCTAssertTrue(HelperPolicy.isAdmin(uid: 0))
        let nobody = try XCTUnwrap(getpwnam("nobody")).pointee.pw_uid
        XCTAssertFalse(HelperPolicy.isAdmin(uid: nobody))
    }

    func testUnknownUserIsNotAdmin() {
        XCTAssertFalse(HelperPolicy.isAdmin(uid: 424_242))
    }

    // MARK: - The decision

    func testDecisionTable() {
        XCTAssertTrue(HelperPolicy.allows(requireAdmin: false, callerIsAdmin: false))
        XCTAssertTrue(HelperPolicy.allows(requireAdmin: false, callerIsAdmin: true))
        XCTAssertTrue(HelperPolicy.allows(requireAdmin: true, callerIsAdmin: true))
        XCTAssertFalse(HelperPolicy.allows(requireAdmin: true, callerIsAdmin: false))
    }
}
