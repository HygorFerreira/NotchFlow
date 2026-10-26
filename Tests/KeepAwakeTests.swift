import Foundation
import IOKit.pwr_mgt

@main
struct KeepAwakeTests {
    @MainActor
    static func main() {
        func assertionCount() -> Int {
            var result: Unmanaged<CFDictionary>?
            precondition(IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess)
            let processes = result!.takeRetainedValue() as NSDictionary
            let assertions = processes[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] as? [[String: Any]] ?? []
            return assertions.filter { ($0[kIOPMAssertionNameKey] as? String) == "NotchFlow timed focus session" }.count
        }

        let controller = KeepAwakeController()
        defer { controller.stop() }
        precondition(assertionCount() == 0)
        controller.start(minutes: 15)
        precondition(controller.error == nil && controller.endsAt != nil)
        precondition(assertionCount() == 1, "A session must hold an actual macOS power assertion")
        controller.start(minutes: 30)
        precondition(assertionCount() == 1, "Replacing a session must release the previous assertion")
        let end = controller.endsAt!
        controller.stopIfExpired(at: end.addingTimeInterval(-1))
        precondition(assertionCount() == 1)
        controller.stopIfExpired(at: end)
        precondition(controller.endsAt == nil && assertionCount() == 0, "Expiration must release the OS assertion")
        controller.start(minutes: 1)
        controller.stop()
        controller.stop()
        precondition(controller.endsAt == nil && assertionCount() == 0, "Stopping must be idempotent")
        print("PASS: real macOS sleep assertion, replacement, expiration and manual release")
    }
}
