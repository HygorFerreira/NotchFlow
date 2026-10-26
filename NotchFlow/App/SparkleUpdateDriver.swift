#if !APPSTORE
import AppKit
import Sparkle

/// Sparkle's standard UI downloads and installs the signed archive in place.
/// This driver is absent from the App Store target, including its framework.
@MainActor
final class SparkleUpdateDriver: NSObject, AppUpdateDriver, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    var onChange: ((AppUpdateState) -> Void)?
    private var state = AppUpdateState() {
        didSet { onChange?(state) }
    }
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: self, userDriverDelegate: self)
    }

    func start() throws {
        try UpdateConfiguration.validate(Bundle.main.infoDictionary ?? [:])
        try controller.updater.start()
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshPreferences() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshPreferences() }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refreshPreferences() }
            }
        ]
        refreshPreferences()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    private func refreshPreferences() {
        state.canCheck = controller.updater.canCheckForUpdates
        state.automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        state.automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        state.isChecking = true
        state.errorMessage = nil
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        state.lastChecked = Date()
        state.errorMessage = nil
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state.availableVersion = item.displayVersionString
        state.isChecking = false
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        state.availableVersion = nil
        state.isChecking = false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        state.errorMessage = String(localized: "Could not update NotchFlow. Try again later.")
        state.isChecking = false
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        state.isChecking = false
        refreshPreferences()
    }

    // This is a menu bar app: let Sparkle show its window without stealing
    // focus on scheduled checks. The menu always provides a manual entry point.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
#endif
