import Foundation
import Combine

/// UI state shared by the menu and Settings. Sparkle owns downloads, signature
/// verification, installation, scheduling and the relaunch of the application.
struct AppUpdateState: Equatable {
    var canCheck = false
    var isChecking = false
    var availableVersion: String?
    var lastChecked: Date?
    var errorMessage: String?
    var automaticallyChecks = true
    var automaticallyDownloads = true
}

@MainActor
protocol AppUpdateDriver: AnyObject {
    var onChange: ((AppUpdateState) -> Void)? { get set }
    func start() throws
    func checkForUpdates()
    func setAutomaticChecks(_ enabled: Bool)
    func setAutomaticDownloads(_ enabled: Bool)
}

/// Validates the bundled trust configuration before starting any update checks.
/// The private signing key never belongs in the application or repository.
enum UpdateConfiguration {
    static func validate(_ info: [String: Any]) throws {
        guard let feed = info["SUFeedURL"] as? String, let url = URL(string: feed),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else {
            throw NSError(domain: "NotchFlow.Updates", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Updates are not configured in this build.")
            ])
        }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared: UpdateChecker = {
        #if APPSTORE || UPDATE_TESTING
        UpdateChecker(driver: nil)
        #else
        UpdateChecker(driver: SparkleUpdateDriver())
        #endif
    }()

    @Published private(set) var state = AppUpdateState()
    private let driver: AppUpdateDriver?
    private var started = false

    init(driver: AppUpdateDriver?) {
        self.driver = driver
        driver?.onChange = { [weak self] state in self?.state = state }
    }

    static var isEnabled: Bool {
        #if APPSTORE
        false
        #else
        true
        #endif
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func start() {
        guard Self.isEnabled, !started, let driver else { return }
        do {
            try driver.start()
            started = true
        } catch {
            state.canCheck = false
            state.isChecking = false
            state.errorMessage = error.localizedDescription
        }
    }

    func checkForUpdates() {
        start()
        guard started, state.canCheck else { return }
        driver?.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard started else { return }
        driver?.setAutomaticChecks(enabled)
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard started else { return }
        driver?.setAutomaticDownloads(enabled)
    }
}
