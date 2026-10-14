import Foundation
import AppKit
import Combine

/// Polls the project's GitHub Releases and, when the latest published release
/// is newer than the running build, publishes it so the menu bar can offer a
/// "New version available" item that opens the release page.
///
/// The `MenuBarExtra` body re-evaluates whenever this `ObservableObject`
/// changes — same reason `FocusMenuState` exists: the `AppDelegate`'s own
/// properties don't drive the menu.
///
/// The Mac App Store build is compiled with the `APPSTORE` condition
/// (see `scripts/appstore.sh`): the store delivers its updates, so there the
/// checker never touches the network.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// The newer release, once one is found. `nil` means "up to date / not
    /// checked yet".
    @Published private(set) var availableUpdate: Release?

    /// A release worth surfacing to the user.
    struct Release: Equatable {
        /// Human-readable version, with any leading "v" stripped (e.g. "0.0.3").
        let version: String
        /// The GitHub release page to open when the user clicks the item.
        let url: URL
    }

    /// `owner/repo` for the releases endpoint.
    private static let releaseRepository = "HygorFerreira/NotchFlow"

    /// Don't hammer the API — re-check at most this often.
    private let minInterval: TimeInterval = 60 * 60 * 6
    private var lastCheck: Date?
    private let session: URLSession
    private let installedVersion: String?

    init(session: URLSession = .shared, currentVersion: String? = nil) {
        self.session = session
        self.installedVersion = currentVersion
    }

    /// `false` in the App Store build, where the store handles updates.
    static var isEnabled: Bool {
        #if APPSTORE
        return false
        #else
        return true
        #endif
    }

    /// Set while a manual check (from Settings) is in flight.
    @Published private(set) var isChecking = false
    /// When the last check finished, successful or not.
    @Published private(set) var lastChecked: Date?
    /// A failed request must not be presented as a successful version check.
    @Published private(set) var checkFailed = false
    @Published private(set) var errorMessage: String?

    /// The running app version (`CFBundleShortVersionString`), e.g. "0.0.1".
    var currentVersion: String {
        installedVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fetch the latest release and publish it if it's newer than the running
    /// build. Safe to call repeatedly; throttled by `minInterval` unless
    /// `force` is set. Failed checks preserve any previously found update and
    /// expose an error state in Settings.
    func checkForUpdates(force: Bool = false) {
        guard Self.isEnabled, !isChecking else { return }
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < minInterval {
            return
        }
        lastCheck = Date()

        guard let url = URL(string: "https://api.github.com/repos/\(Self.releaseRepository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchFlow", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // Fully-qualified: the app defines its own `Task` model, which would
        // otherwise shadow Swift concurrency's `Task` here.
        isChecking = true
        checkFailed = false
        errorMessage = nil
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer {
                self.isChecking = false
                self.lastChecked = Date()
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                guard http.statusCode == 200 else {
                    self.checkFailed = true
                    switch http.statusCode {
                    case 404:
                        self.errorMessage = String(localized: "No public release is available. Releases must be accessible without signing in.")
                    case 403, 429:
                        self.errorMessage = String(localized: "GitHub temporarily refused the check. Try again later.")
                    default:
                        self.errorMessage = String(localized: "Could not check for updates. Try again later.")
                    }
                    return
                }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                try self.apply(release)
            } catch {
                self.checkFailed = true
                self.errorMessage = String(localized: "Could not check for updates. Try again later.")
            }
        }
    }

    /// Open the pending release's GitHub page in the default browser.
    func openReleasePage() {
        guard let update = availableUpdate else { return }
        NSWorkspace.shared.open(update.url)
    }

    // MARK: - Private

    private func apply(_ release: GitHubRelease) throws {
        // Skip drafts and prereleases — only stable, published releases count.
        guard !release.draft, !release.prerelease else { throw URLError(.cannotParseResponse) }
        let latest = Self.normalized(release.tagName)
        guard Self.components(latest) != nil, Self.components(Self.normalized(currentVersion)) != nil,
              let pageURL = URL(string: release.htmlURL), pageURL.scheme == "https",
              pageURL.host == "github.com", pageURL.user == nil, pageURL.password == nil,
              pageURL.path.hasPrefix("/\(Self.releaseRepository)/releases/tag/") else {
            throw URLError(.cannotParseResponse)
        }
        guard Self.isNewer(latest, than: Self.normalized(currentVersion)) else {
            availableUpdate = nil
            return
        }
        availableUpdate = Release(version: latest, url: pageURL)
    }

    /// Strip a leading "v" and trim whitespace: "v0.0.3" -> "0.0.3".
    private static func normalized(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Stable numeric versions; absent components are zero, so "1.2" < "1.2.1".
    /// Malformed tags must never become a successful "up to date" result.
    private static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : nil
    }
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        guard let a = components(normalized(lhs)), let b = components(normalized(rhs)) else { return false }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

/// The subset of the GitHub release payload we care about.
private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}
