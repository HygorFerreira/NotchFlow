import Foundation

@main
struct UpdateCheckerTests {
    @MainActor
    static func main() throws {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        let valid: [String: Any] = ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": key]
        try UpdateConfiguration.validate(valid)
        for bad in [
            [:],
            ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": key],
            ["SUFeedURL": "https://user:password@example.com/feed", "SUPublicEDKey": key],
            ["SUFeedURL": "https://example.com/feed", "SUPublicEDKey": "not-a-key"],
            ["SUFeedURL": "https://example.com/feed", "SUPublicEDKey": Data(repeating: 0, count: 31).base64EncodedString()]
        ] as [[String: Any]] {
            do {
                try UpdateConfiguration.validate(bad)
                preconditionFailure("An invalid trust configuration was accepted")
            } catch {}
        }

        let driver = FakeUpdateDriver()
        let checker = UpdateChecker(driver: driver)
        checker.start()
        #if APPSTORE
        checker.checkForUpdates()
        checker.setAutomaticChecks(false)
        checker.setAutomaticDownloads(false)
        precondition(driver.starts == 0 && driver.checks == 0 && driver.preferenceChanges == 0)
        print("App Store updater isolation passed")
        #else
        precondition(driver.starts == 1 && checker.state.canCheck)
        checker.start()
        precondition(driver.starts == 1)
        checker.checkForUpdates()
        precondition(driver.checks == 1 && checker.state.isChecking)
        checker.checkForUpdates()
        precondition(driver.checks == 1, "A second check must not start during an update session")
        driver.state.isChecking = false
        driver.state.canCheck = true
        driver.state.availableVersion = "1.3.0"
        driver.state.lastChecked = Date()
        precondition(checker.state.availableVersion == "1.3.0" && checker.state.lastChecked != nil)
        checker.setAutomaticChecks(false)
        checker.setAutomaticDownloads(false)
        precondition(!checker.state.automaticallyChecks && !checker.state.automaticallyDownloads)
        checker.checkForUpdates()
        precondition(driver.checks == 2, "Disabling scheduled checks must keep manual checks available")
        driver.state.errorMessage = "Network unavailable"
        precondition(checker.state.errorMessage == "Network unavailable")

        let failing = FakeUpdateDriver()
        failing.startError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing signing key"])
        let broken = UpdateChecker(driver: failing)
        broken.checkForUpdates()
        precondition(!broken.state.canCheck && broken.state.errorMessage == "Missing signing key")
        precondition(failing.checks == 0)
        // A corrected configuration can be retried without restarting the app.
        failing.startError = nil
        broken.checkForUpdates()
        precondition(failing.starts == 2 && failing.checks == 1)
        print("In-app update state and configuration tests passed")
        #endif
    }
}

@MainActor
final class FakeUpdateDriver: AppUpdateDriver {
    var onChange: ((AppUpdateState) -> Void)?
    var state = AppUpdateState() { didSet { onChange?(state) } }
    var starts = 0
    var checks = 0
    var preferenceChanges = 0
    var startError: Error?

    func start() throws {
        starts += 1
        if let startError { throw startError }
        state.canCheck = true
    }
    func checkForUpdates() {
        checks += 1
        state.canCheck = false
        state.isChecking = true
    }
    func setAutomaticChecks(_ enabled: Bool) {
        preferenceChanges += 1
        state.automaticallyChecks = enabled
    }
    func setAutomaticDownloads(_ enabled: Bool) {
        preferenceChanges += 1
        state.automaticallyDownloads = enabled
    }
}
