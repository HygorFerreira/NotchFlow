import Foundation

@main
struct FocusTimerTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFlowTimer-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(fileURL: root.appendingPathComponent("data.json"), taskReminderScheduler: { _ in })
        store.settings.notificationsEnabled = false
        store.settings.playSound = false
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let timer = FocusTimer(store: store, now: { now })

        timer.start(durationMinutes: Int.max)
        precondition(timer.total == 180 * 60)
        timer.stop(record: false)
        timer.start(durationMinutes: 0)
        precondition(timer.total == 60)
        timer.stop(record: false)

        timer.start(durationMinutes: 2)
        for _ in 0..<10 {
            now = now.addingTimeInterval(0.25)
            timer.pause()
            now = now.addingTimeInterval(10) // Paused time never counts.
            timer.togglePause()
        }
        precondition(abs(timer.remaining - 117.5) < 0.001)
        precondition(timer.timeLabel == "01:58")
        now = now.addingTimeInterval(60)
        timer.stop()
        precondition(abs(store.sessions.last!.duration - 62.5) < 0.001)
        precondition(!store.sessions.last!.completed)

        // Pausing after the deadline (e.g. immediately after wake) completes once.
        timer.start(durationMinutes: 1)
        now = now.addingTimeInterval(90)
        timer.pause()
        precondition(timer.state == .idle && store.sessions.count == 2)
        precondition(store.sessions.last!.completed && store.sessions.last!.duration == 60)
        timer.stop()
        precondition(store.sessions.count == 2)

        store.add(title: "Live task", estimate: 5)
        let task = store.tasks[0]
        store.onTaskUpdated = { timer.taskDidChange($0) }
        store.onTaskDeactivated = { timer.stopIfActive($0, record: $1) }
        timer.start(task: task)
        now = now.addingTimeInterval(90)
        var edited = task
        edited.title = "Renamed"
        edited.estimateMinutes = 3
        store.update(edited)
        precondition(timer.remaining == 90 && timer.activeTask?.title == "Renamed")
        store.toggleDone(store.tasks[0])
        precondition(timer.state == .idle && store.tasks[0].focusedSeconds == 90)
        timer.start(durationMinutes: 1)
        now = now.addingTimeInterval(5)
        timer.stop()
        precondition(store.sessions.count == 3, "Accidental short blocks must not be recorded")
        print("PASS: timer bounds, subsecond pauses, elapsed completion, edits, task completion and short blocks")
    }
}
