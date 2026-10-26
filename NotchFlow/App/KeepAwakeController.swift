import Foundation
import Combine
import IOKit.pwr_mgt

/// An idle-sleep assertion, scoped to a finite user-selected session. It does
/// not prevent an explicit Sleep command or change lid-close behavior.
@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()
    @Published private(set) var endsAt: Date?
    @Published private(set) var error: String?
    private var assertion: IOPMAssertionID?
    private var timer: AnyCancellable?

    func start(minutes: Int) {
        stop()
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "NotchFlow timed focus session" as CFString, &identifier)
        guard result == kIOReturnSuccess else {
            error = String(localized: "Could not keep this Mac awake")
            return
        }
        assertion = identifier
        endsAt = Date().addingTimeInterval(Double(min(180, max(1, minutes))) * 60)
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in self?.stopIfExpired(at: now) }
    }

    func stopIfExpired(at now: Date) {
        guard let end = endsAt, now >= end else { return }
        stop()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let assertion { IOPMAssertionRelease(assertion) }
        assertion = nil
        endsAt = nil
        error = nil
    }
}
