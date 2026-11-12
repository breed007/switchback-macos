import XCTest

final class UpdateCheckTests: XCTestCase {
    private typealias V = UpdateCheck.Version

    func testVersionsCompareByNumberNotText() {
        XCTAssertLessThan(V("0.9.2")!, V("0.10.0")!)
        XCTAssertLessThan(V("0.6.1")!, V("v0.7.0")!)
        XCTAssertEqual(V("0.7")!, V("0.7.0")!)
        XCTAssertFalse(V("0.7.0")! < V("0.7")!)
        XCTAssertEqual(V("v1.2.3")!.description, "1.2.3")
    }

    func testOnlyPlainVersionsParse() {
        for bad in ["", "v", "0.7.1-beta", "0..1", "0.7.", "1.2.3.4.5", "x1.0", "١.٢"] {
            XCTAssertNil(V(bad), bad)
        }
    }

    private func json(tag: String = "v0.7.1",
                      url: String = "https://github.com/breed007/switchback-macos/releases/tag/v0.7.1") -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": false])
    }

    func testParsesALatestReleaseResponse() {
        XCTAssertEqual(UpdateCheck.parseLatest(json()),
                       .init(version: V("0.7.1")!,
                             url: URL(string: "https://github.com/breed007/switchback-macos/releases/tag/v0.7.1")!))
    }

    func testRejectsAnythingButOurReleasePages() {
        for url in ["http://github.com/breed007/switchback-macos/releases/tag/v0.7.1",
                    "https://evil.example/breed007/switchback-macos/releases/tag/v0.7.1",
                    "https://github.com/someone/switchback-macos/releases/tag/v0.7.1",
                    "https://github.com/breed007/switchback-macos/releases/../../other/releases/x",
                    "https://user@github.com/breed007/switchback-macos/releases/tag/v0.7.1",
                    "https://github.com:8443/breed007/switchback-macos/releases/tag/v0.7.1",
                    "https://github.com/breed007/switchback-macos/archive/v0.7.1.zip"] {
            XCTAssertNil(UpdateCheck.parseLatest(json(url: url)), url)
        }
        XCTAssertNil(UpdateCheck.parseLatest(json(tag: "nightly")))
        XCTAssertNil(UpdateCheck.parseLatest(Data("not json".utf8)))
        XCTAssertNil(UpdateCheck.parseLatest(Data("[]".utf8)))
    }

    func testOnlyANewerReleaseIsAnUpdate() {
        let release = UpdateCheck.parseLatest(json())
        XCTAssertNotNil(UpdateCheck.update(release, over: V("0.7.0")!))
        XCTAssertNil(UpdateCheck.update(release, over: V("0.7.1")!))
        XCTAssertNil(UpdateCheck.update(release, over: V("0.8.0")!))
        XCTAssertNil(UpdateCheck.update(nil, over: V("0.7.0")!))
    }

    func testChecksAreDueOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now), "clock went backward")
    }

    func testHomebrewInstallsAreFoundInEitherCaskroom() {
        XCTAssertTrue(UpdateCheck.installedWithHomebrew { $0 == "/opt/homebrew/Caskroom/switchback" })
        XCTAssertTrue(UpdateCheck.installedWithHomebrew { $0 == "/usr/local/Caskroom/switchback" })
        XCTAssertFalse(UpdateCheck.installedWithHomebrew { $0 == "/opt/homebrew/Caskroom/crossbar" })
    }

    func testOnlyAForcedPolicyTurnsChecksOff() {
        XCTAssertTrue(UpdateCheck.disabledByPolicy(isForced: { _ in true }, value: { _ in true }))
        XCTAssertFalse(UpdateCheck.disabledByPolicy(isForced: { _ in false }, value: { _ in true }), "user-set")
        XCTAssertFalse(UpdateCheck.disabledByPolicy(isForced: { _ in true }, value: { _ in false }))
        XCTAssertFalse(UpdateCheck.disabledByPolicy(isForced: { _ in true }, value: { _ in "yes" }))
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var fetched: [URL] = []

    override func setUp() async throws {
        let name = "com.breed007.switchback.tests.updates"
        defaults = UserDefaults(suiteName: name)
        defaults.removePersistentDomain(forName: name)
        fetched = []
    }

    private func checker(installed: String = "0.7.0", answer: Result<String, Error> = .success("v0.7.1"),
                         policy: Bool = false) -> UpdateChecker {
        UpdateChecker(preferences: UpdatePreferences(defaults), installed: UpdateCheck.Version(installed)!,
                      fetch: { url in
                          self.fetched.append(url)
                          let tag = try answer.get()
                          return try JSONSerialization.data(withJSONObject: [
                              "tag_name": tag,
                              "html_url": "https://github.com/breed007/switchback-macos/releases/tag/\(tag)"])
                      },
                      policyDisabled: { policy })
    }

    func testNothingIsFetchedUntilTheUserSaysYes() async {
        let updates = checker()
        XCTAssertFalse(updates.isAutomatic)
        // The checks run in Tasks: wait for any that started, then look.
        let started = [updates.checkIfDue(), updates.start()].compactMap { $0 }
        for task in started { _ = await task.value }
        XCTAssertTrue(started.isEmpty, "no check starts before consent")
        XCTAssertTrue(fetched.isEmpty)

        updates.setAutomatic(false)
        XCTAssertNil(updates.checkIfDue())
        XCTAssertTrue(fetched.isEmpty)
        updates.stop()
    }

    func testTurningChecksOnChecksRightAway() async {
        let updates = checker()
        updates.setAutomatic(true)
        guard let check = updates.checkIfDue() else { return XCTFail("a first check is always due") }
        _ = await check.value
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(updates.checkIfDue(), "not due again for a day")
        updates.stop()
    }

    func testSimultaneousChecksShareOneRequest() async {
        let updates = checker()
        async let first = updates.checkNow()
        async let second = updates.checkNow()
        let outcomes = await [first, second]
        XCTAssertEqual(outcomes[0], outcomes[1])
        XCTAssertEqual(fetched.count, 1)
    }

    func testCheckNowFindsAndRemembersANewerRelease() async {
        let updates = checker()
        let outcome = await updates.checkNow()
        XCTAssertEqual(fetched, [URL(string: "https://api.github.com/repos/breed007/switchback-macos/releases/latest")!])
        guard case .available(let release) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(release.version.description, "0.7.1")
        XCTAssertEqual(checker().available?.version.description, "0.7.1", "survives a new instance")
        XCTAssertNil(checker(installed: "0.7.1").available, "gone once installed")
    }

    func testUpToDateAndFailedChecks() async {
        let upToDate = await checker(installed: "0.7.1").checkNow()
        let offline = await checker(answer: .failure(URLError(.notConnectedToInternet))).checkNow()
        let notARelease = await checker(answer: .success("nightly")).checkNow()
        XCTAssertEqual(upToDate, .upToDate(UpdateCheck.Version("0.7.1")!))
        XCTAssertEqual(offline, .failed)
        XCTAssertEqual(notARelease, .failed)
        XCTAssertNotNil(UpdatePreferences(defaults).lastUpdateCheck, "a failed attempt still counts toward the day")
    }

    func testPolicyWinsOverEverything() async {
        UpdatePreferences(defaults).checkForUpdates = true
        UpdatePreferences(defaults).latestKnownRelease = ("0.9.0", "https://github.com/breed007/switchback-macos/releases/tag/v0.9.0")
        let updates = checker(policy: true)
        XCTAssertFalse(updates.isAutomatic)
        XCTAssertNil(updates.available)
        let outcome = await updates.checkNow()
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testTheRequestCarriesOnlyFixedHeaders() {
        let request = UpdateChecker.request(for: UpdateCheck.product.latestReleaseAPI)
        let headers = request.allHTTPHeaderFields ?? [:]
        XCTAssertEqual(Set(headers.keys), ["Accept", "User-Agent", "Accept-Language"])
        XCTAssertEqual(headers["Accept-Language"], "en", "not the user's languages")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testAStoredReleaseOutsideOurRepoIsIgnored() {
        UpdatePreferences(defaults).latestKnownRelease = ("9.0.0", "https://evil.example/releases/tag/v9.0.0")
        XCTAssertNil(checker().available)
    }
}
