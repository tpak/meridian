// Copyright © 2015 Abhishek Banthia

@testable import Meridian
import XCTest

// MARK: - Mock Network Fetcher

/// A mock network fetcher that returns pre-configured responses without hitting real URLs.
final class MockNetworkFetcher: VersionUpdateNetworkFetching {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?

    func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }
        let data = mockData ?? Data()
        let response = mockResponse ?? HTTPURLResponse(url: url,
                                                        statusCode: 200,
                                                        httpVersion: nil,
                                                        headerFields: nil)!
        return (data, response)
    }

    /// Convenience: configure the mock to return a valid GitHub release JSON.
    func configureRelease(tagName: String, body: String? = nil, htmlURL: String = "https://github.com/nickhumbir/clocker/releases/tag/1.0.0") {
        var dict: [String: Any] = [
            "tag_name": tagName,
            "name": "Release \(tagName)",
            "html_url": htmlURL
        ]
        if let body = body {
            dict["body"] = body
        }
        mockData = try? JSONSerialization.data(withJSONObject: dict, options: [])
        mockResponse = nil // Will use default 200 response
    }
}

// MARK: - Version Comparison Tests

final class VersionComparisonTests: XCTestCase {

    func testNewerPatchVersion() {
        XCTAssertTrue(VersionUpdateHandler.isVersion("1.0.1", newerThan: "1.0.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(VersionUpdateHandler.isVersion("1.1", newerThan: "1.0"))
        XCTAssertTrue(VersionUpdateHandler.isVersion("1.1.0", newerThan: "1.0.0"))
    }

    func testNewerMajorVersion() {
        XCTAssertTrue(VersionUpdateHandler.isVersion("2.0", newerThan: "1.9.9"))
        XCTAssertTrue(VersionUpdateHandler.isVersion("2.0.0", newerThan: "1.9.9"))
    }

    func testSameVersion() {
        XCTAssertFalse(VersionUpdateHandler.isVersion("1.0.0", newerThan: "1.0.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(VersionUpdateHandler.isVersion("1.0.0", newerThan: "1.0.1"))
        XCTAssertFalse(VersionUpdateHandler.isVersion("1.9.9", newerThan: "2.0"))
    }

    func testStringCompareVersion() {
        XCTAssertEqual("1.0.0".compareVersion("1.0.1"), .orderedAscending)
        XCTAssertEqual("1.0.1".compareVersion("1.0.0"), .orderedDescending)
        XCTAssertEqual("1.0.0".compareVersion("1.0.0"), .orderedSame)
    }

    func testStringCompareVersionDescending() {
        XCTAssertEqual("1.0.0".compareVersionDescending("1.0.1"), .orderedDescending)
        XCTAssertEqual("1.0.1".compareVersionDescending("1.0.0"), .orderedAscending)
        XCTAssertEqual("1.0.0".compareVersionDescending("1.0.0"), .orderedSame)
    }
}

// MARK: - GitHubRelease Tests

final class GitHubReleaseTests: XCTestCase {

    func testVersionStripsLeadingV() {
        let json = """
        {"tag_name": "v1.2.3", "name": "Release", "body": "Notes", "html_url": "https://example.com"}
        """.data(using: .utf8)!

        let release = try! JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.tagName, "v1.2.3")
    }

    func testVersionWithoutPrefix() {
        let json = """
        {"tag_name": "1.2.3", "name": "Release", "body": null, "html_url": "https://example.com"}
        """.data(using: .utf8)!

        let release = try! JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.version, "1.2.3")
    }

    func testOptionalFields() {
        let json = """
        {"tag_name": "1.0.0", "html_url": "https://example.com"}
        """.data(using: .utf8)!

        let release = try! JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertNil(release.name)
        XCTAssertNil(release.body)
    }
}

// MARK: - Check Interval Logic Tests

final class VersionUpdateHandlerCheckIntervalTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "VersionUpdateHandlerTests")!
        defaults.removePersistentDomain(forName: "VersionUpdateHandlerTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "VersionUpdateHandlerTests")
        super.tearDown()
    }

    func testShouldCheckWhenNeverCheckedBefore() {
        let handler = VersionUpdateHandler(defaults: defaults)
        XCTAssertTrue(handler.shouldCheck())
    }

    func testShouldNotCheckIfCheckedRecently() {
        let handler = VersionUpdateHandler(defaults: defaults)
        handler.checkInterval = 86_400 // 1 day

        // Simulate a check 1 hour ago
        defaults.set(Date(timeIntervalSinceNow: -3600), forKey: "VersionUpdate_LastCheckDate")

        XCTAssertFalse(handler.shouldCheck())
    }

    func testShouldCheckIfCheckIntervalElapsed() {
        let handler = VersionUpdateHandler(defaults: defaults)
        handler.checkInterval = 86_400 // 1 day

        // Simulate a check 2 days ago
        defaults.set(Date(timeIntervalSinceNow: -172_800), forKey: "VersionUpdate_LastCheckDate")

        XCTAssertTrue(handler.shouldCheck())
    }

    func testPreviewModeAlwaysChecks() {
        let handler = VersionUpdateHandler(defaults: defaults)
        handler.previewMode = true

        // Even with a recent check, preview mode should always check
        defaults.set(Date(), forKey: "VersionUpdate_LastCheckDate")

        XCTAssertTrue(handler.shouldCheck())
    }

    func testShouldNotCheckIfRemindedRecently() {
        let handler = VersionUpdateHandler(defaults: defaults)
        handler.checkInterval = 86_400

        // User asked to be reminded 1 hour ago
        defaults.set(Date(timeIntervalSinceNow: -3600), forKey: "VersionUpdate_LastRemindedDate")

        XCTAssertFalse(handler.shouldCheck())
    }

    func testShouldCheckIfRemindIntervalElapsed() {
        let handler = VersionUpdateHandler(defaults: defaults)
        handler.checkInterval = 86_400

        // User asked to be reminded 2 days ago
        defaults.set(Date(timeIntervalSinceNow: -172_800), forKey: "VersionUpdate_LastRemindedDate")

        XCTAssertTrue(handler.shouldCheck())
    }
}

// MARK: - Skip Version Tests

final class VersionUpdateHandlerSkipTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "VersionUpdateHandlerSkipTests")!
        defaults.removePersistentDomain(forName: "VersionUpdateHandlerSkipTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "VersionUpdateHandlerSkipTests")
        super.tearDown()
    }

    func testSkippedVersionIsPersistedInDefaults() {
        defaults.set("2.0.0", forKey: "VersionUpdate_SkippedVersion")
        let skippedVersion = defaults.string(forKey: "VersionUpdate_SkippedVersion")
        XCTAssertEqual(skippedVersion, "2.0.0")
    }

    func testNoSkippedVersionByDefault() {
        let skippedVersion = defaults.string(forKey: "VersionUpdate_SkippedVersion")
        XCTAssertNil(skippedVersion)
    }
}

// MARK: - Mock Network Fetcher Tests

final class VersionUpdateHandlerNetworkTests: XCTestCase {

    func testMockFetcherReturnsConfiguredRelease() async throws {
        let fetcher = MockNetworkFetcher()
        fetcher.configureRelease(tagName: "v2.0.0", body: "Bug fixes")

        let url = URL(string: "https://api.github.com/repos/test/test/releases/latest")!
        let (data, _) = try await fetcher.fetchData(from: url)

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        XCTAssertEqual(release.version, "2.0.0")
        XCTAssertEqual(release.body, "Bug fixes")
    }

    func testMockFetcherThrowsConfiguredError() async {
        let fetcher = MockNetworkFetcher()
        fetcher.mockError = URLError(.notConnectedToInternet)

        let url = URL(string: "https://api.github.com/repos/test/test/releases/latest")!

        do {
            _ = try await fetcher.fetchData(from: url)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}
