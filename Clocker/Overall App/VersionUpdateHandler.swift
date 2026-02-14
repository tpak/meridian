// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit

// MARK: - Network Fetching Protocol (for testability)

/// Protocol for fetching data from a URL, allowing tests to inject a mock.
protocol VersionUpdateNetworkFetching {
    func fetchData(from url: URL) async throws -> (Data, URLResponse)
}

/// Default implementation using URLSession.
struct URLSessionNetworkFetcher: VersionUpdateNetworkFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        return try await session.data(from: url)
    }
}

// MARK: - GitHub Release Model

/// Represents the response from the GitHub Releases API.
struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
    }

    /// Extracts a clean semantic version string from the tag (strips leading "v" or "V").
    var version: String {
        let tag = tagName
        if tag.lowercased().hasPrefix("v") {
            return String(tag.dropFirst())
        }
        return tag
    }
}

// MARK: - VersionUpdateHandler

final class VersionUpdateHandler {

    // MARK: Configuration

    /// The HTTPS URL to check for the latest release.
    /// Defaults to the GitHub Releases API endpoint for this repo.
    /// Can be overridden via the Info.plist key "VersionUpdateCheckURL".
    static let defaultUpdateCheckURL = "https://api.github.com/repos/nickhumbir/clocker/releases/latest"

    /// The HTTPS URL where users can download the latest release.
    static let defaultDownloadURL = "https://github.com/nickhumbir/clocker/releases/latest"

    // MARK: UserDefaults Keys

    private enum DefaultsKey {
        static let skippedVersion = "VersionUpdate_SkippedVersion"
        static let lastCheckDate = "VersionUpdate_LastCheckDate"
        static let lastRemindedDate = "VersionUpdate_LastRemindedDate"
    }

    // MARK: Properties

    private let networkFetcher: VersionUpdateNetworkFetching
    private let defaults: UserDefaults
    private let bundle: Bundle

    /// Minimum interval between automatic update checks, in seconds. Default: 1 day.
    var checkInterval: TimeInterval = 86_400

    /// When true, forces an update check regardless of interval or skipped version.
    var previewMode: Bool = false

    // MARK: Initialization

    init(networkFetcher: VersionUpdateNetworkFetching = URLSessionNetworkFetcher(),
         defaults: UserDefaults = .standard,
         bundle: Bundle = .main) {
        self.networkFetcher = networkFetcher
        self.defaults = defaults
        self.bundle = bundle
    }

    // MARK: Public API

    /// Performs an update check if enough time has elapsed since the last check.
    /// Shows an alert on the main thread if a newer version is available.
    func checkForUpdatesIfNeeded() {
        guard shouldCheck() else {
            Logger.info("VersionUpdateHandler: Skipping update check (checked recently or user deferred)")
            return
        }
        Task {
            await checkForUpdates()
        }
    }

    /// Unconditionally checks for updates (e.g., from a manual "Check for Updates" menu item).
    @MainActor
    func checkForUpdates() async {
        Logger.info("VersionUpdateHandler: Checking for updates...")

        guard let updateURL = resolvedUpdateCheckURL() else {
            Logger.info("VersionUpdateHandler: Invalid update check URL")
            return
        }

        do {
            let release = try await fetchLatestRelease(from: updateURL)
            defaults.set(Date(), forKey: DefaultsKey.lastCheckDate)

            let currentVersion = currentAppVersion()
            Logger.info("VersionUpdateHandler: Current version \(currentVersion), latest version \(release.version)")

            guard VersionUpdateHandler.isVersion(release.version, newerThan: currentVersion) else {
                Logger.info("VersionUpdateHandler: App is up to date")
                return
            }

            // Check if user skipped this version
            if !previewMode, let skipped = defaults.string(forKey: DefaultsKey.skippedVersion),
               skipped == release.version {
                Logger.info("VersionUpdateHandler: User skipped version \(release.version)")
                return
            }

            // Check remind-me-later
            if !previewMode, let lastReminded = defaults.object(forKey: DefaultsKey.lastRemindedDate) as? Date,
               Date().timeIntervalSince(lastReminded) < checkInterval {
                Logger.info("VersionUpdateHandler: User asked to be reminded later; not enough time has passed")
                return
            }

            showUpdateAlert(for: release)
        } catch {
            Logger.info("VersionUpdateHandler: Failed to check for updates - \(error.localizedDescription)")
        }
    }

    // MARK: Version Comparison (internal for testing)

    /// Returns true if `candidate` is a newer semantic version than `current`.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        return current.compareVersion(candidate) == .orderedAscending
    }

    // MARK: Private - Networking

    private func resolvedUpdateCheckURL() -> URL? {
        // Allow override from Info.plist
        if let plistURL = bundle.object(forInfoDictionaryKey: "VersionUpdateCheckURL") as? String,
           let url = URL(string: plistURL),
           url.scheme?.lowercased() == "https" {
            return url
        }
        return URL(string: VersionUpdateHandler.defaultUpdateCheckURL)
    }

    private func fetchLatestRelease(from url: URL) async throws -> GitHubRelease {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Clocker-macOS-App", forHTTPHeaderField: "User-Agent")

        // Use the protocol-based fetcher
        let (data, response) = try await networkFetcher.fetchData(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    // MARK: Private - Check Interval Logic

    /// Returns true if enough time has elapsed since the last check (or if previewMode is on).
    func shouldCheck() -> Bool {
        if previewMode { return true }

        // Respect remind-me-later
        if let lastReminded = defaults.object(forKey: DefaultsKey.lastRemindedDate) as? Date,
           Date().timeIntervalSince(lastReminded) < checkInterval {
            return false
        }

        guard let lastCheck = defaults.object(forKey: DefaultsKey.lastCheckDate) as? Date else {
            return true // Never checked before
        }
        return Date().timeIntervalSince(lastCheck) >= checkInterval
    }

    // MARK: Private - Current Version

    private func currentAppVersion() -> String {
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        if let version = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String {
            return version
        }
        return "0.0.0"
    }

    // MARK: Private - Alert Presentation

    @MainActor
    private func showUpdateAlert(for release: GitHubRelease) {
        Logger.info("VersionUpdateHandler: Showing update alert for version \(release.version)")

        let alert = NSAlert()
        alert.messageText = "A new version of Clocker is available!"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Remind Me Later")

        // Build informative text with version and truncated release notes
        var info = "Version \(release.version) is now available (you have \(currentAppVersion()))."
        if let notes = release.body, !notes.isEmpty {
            let maxNotesLength = 500
            let truncatedNotes = notes.count > maxNotesLength
                ? String(notes.prefix(maxNotesLength)) + "..."
                : notes
            info += "\n\nRelease Notes:\n\(truncatedNotes)"
        }
        alert.informativeText = info

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Download
            let downloadURLString = release.htmlURL
            if let url = URL(string: downloadURLString) {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            // Skip This Version
            defaults.set(release.version, forKey: DefaultsKey.skippedVersion)
            Logger.info("VersionUpdateHandler: User skipped version \(release.version)")
        case .alertThirdButtonReturn:
            // Remind Me Later
            defaults.set(Date(), forKey: DefaultsKey.lastRemindedDate)
            Logger.info("VersionUpdateHandler: User chose to be reminded later")
        default:
            break
        }
    }
}

// MARK: - String Version Comparison (kept for backward compatibility)

extension String {
    func compareVersion(_ version: String) -> ComparisonResult {
        return compare(version,
                       options: CompareOptions.numeric,
                       range: nil,
                       locale: nil)
    }

    func compareVersionDescending(_ version: String) -> ComparisonResult {
        let comparisonResult = (0 - compareVersion(version).rawValue)
        switch comparisonResult {
        case -1:
            return ComparisonResult.orderedAscending
        case 0:
            return ComparisonResult.orderedSame
        case 1:
            return ComparisonResult.orderedDescending
        default:
            Logger.info("Invalid Comparison Result")
            return .orderedSame
        }
    }
}
