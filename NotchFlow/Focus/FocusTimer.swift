import Foundation
import SwiftUI

/// Focus timer engine. Drives the collapsed-pill countdown + progress bar.
@MainActor
final class FocusTimer: ObservableObject {
    enum State: Equatable { case idle, running, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var activeTask: Task?

    private var timer: Timer?
    private var startedAt: Date?
    /// Wall-clock moment the running block ends. The countdown is derived from
    /// it on every tick, so it stays right across sleep, App Nap and a busy
    /// main thread (a plain "minus one per tick" counter froze while the Mac
    /// slept). `nil` while paused or idle.
    private var endsAt: Date?
    private unowned let store: Store
    private let now: () -> Date

    /// Aborted blocks shorter than this are not recorded, so starting a task by
    /// mistake and stopping it right away doesn't light up the activity grid.
    static let minimumRecordedSeconds: TimeInterval = 60

    init(store: Store, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    var isActive: Bool { state != .idle }

    /// 0…1 elapsed fraction, for the progress bar.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, (total - remaining) / total))
    }

    var timeLabel: String {
        let t = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    func start(task: Task) {
        start(durationMinutes: task.estimateMinutes, task: task)
    }

    /// Start a focus block. `task` may be nil — used by the global hotkey when
    /// the user just wants to start a session without a specific task.
    func start(durationMinutes: Int, task: Task? = nil) {
        stop(record: state != .idle)   // wrap up any prior block first
        if store.settings.notificationsEnabled {
            NotificationService.shared.requestAuthorizationIfNeeded()
        }
        activeTask = task
        total = Self.duration(secondsFor: durationMinutes)
        remaining = total
        startedAt = now()
        resume()
    }

    func togglePause() {
        switch state {
        case .running: pause()
        case .paused:  resume()
        case .idle:    break
        }
    }

    func pause() {
        guard state == .running else { return }
        updateRemaining()
        guard remaining > 0 else { complete(); return }
        state = .paused
        endsAt = nil
        timer?.invalidate()
        timer = nil
    }

    private func resume() {
        state = .running
        endsAt = now().addingTimeInterval(remaining)
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard state == .running else { return }
        updateRemaining()
        if remaining <= 0 { complete() }
    }

    #if DEBUG
    /// Jump ahead in a running block, for the snapshot renderer.
    func debugAdvance(seconds: TimeInterval) {
        endsAt = endsAt?.addingTimeInterval(-seconds)
        updateRemaining()
    }
    #endif

    /// Keep subsecond precision so repeated pauses cannot add or lose time.
    private func updateRemaining() {
        guard let endsAt else { return }
        remaining = min(total, max(0, endsAt.timeIntervalSince(now())))
    }

    private func complete() {
        let taskTitle = activeTask?.title
        finishSession(completed: true)
        if store.settings.playSound { playCompletionSound() }
        if store.settings.notificationsEnabled {
            NotificationService.shared.postFocusComplete(taskTitle: taskTitle)
        }
        reset()
    }

    /// A soft chime for a completed focus block. Prefers the built-in macOS
    /// "Glass" sound (a warm two-note ding) over the harsh system beep, and
    /// falls back to the beep if that named sound isn't available.
    private func playCompletionSound() {
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    /// Stop the current block. `record` persists a session if one was in flight.
    func stop(record: Bool = true) {
        if record { finishSession(completed: false) }
        reset()
    }

    /// Stop the timer only if the running session belongs to `id` (task completed
    /// or deleted). No-op otherwise.
    func stopIfActive(_ id: UUID, record: Bool) {
        guard isActive, activeTask?.id == id else { return }
        stop(record: record)
    }

    /// Keep the running block in step with its task after an edit: a new
    /// title shows in the notch, and a new length re-bases the countdown while
    /// keeping the time already focused. Shortening it below that finishes the
    /// block right away. No-op for other tasks.
    func taskDidChange(_ task: Task) {
        guard isActive, activeTask?.id == task.id else { return }
        activeTask = task
        let newTotal = Self.duration(secondsFor: task.estimateMinutes)
        guard newTotal != total else { return }
        updateRemaining()
        let focused = total - remaining
        total = newTotal
        remaining = max(0, newTotal - focused)
        if state == .running { endsAt = now().addingTimeInterval(remaining) }
        if remaining <= 0 { complete() }
    }

    /// Toggle used by the global hotkey: if a session is in flight, stop it;
    /// otherwise start the first undone task scheduled for today. When the
    /// day's list is empty, fall back to a blank session using the user's
    /// current `focusMinutes` setting so the hotkey always does something.
    func toggleStartStop() {
        if isActive {
            stop(record: true)
            return
        }
        if let next = store.filteredTasks(store.tasks(on: Date())).first(where: { !$0.isDone }) {
            start(task: next)
        } else {
            start(durationMinutes: store.settings.focusMinutes, task: nil)
        }
    }

    private func finishSession(completed: Bool) {
        guard let startedAt else { return }
        updateRemaining()
        // Time actually spent focusing: paused stretches don't count.
        let focused = completed ? total : total - remaining
        guard completed || focused >= Self.minimumRecordedSeconds else { return }
        let session = FocusSession(taskId: activeTask?.id,
                                   startedAt: startedAt,
                                   endedAt: startedAt.addingTimeInterval(focused),
                                   completed: completed)
        store.recordSession(session)
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        state = .idle
        remaining = 0
        total = 0
        activeTask = nil
        startedAt = nil
        endsAt = nil
    }

    private static func duration(secondsFor minutes: Int) -> TimeInterval {
        TimeInterval(min(FocusSettings.focusRange.upperBound,
                         max(FocusSettings.focusRange.lowerBound, minutes))) * 60
    }
}
