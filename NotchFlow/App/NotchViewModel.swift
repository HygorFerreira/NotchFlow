import SwiftUI
import Combine

enum NotchReminder: Equatable {
    case medication(Medication)
    case water
}

/// Drives the notch panel's collapsed ⇄ expanded state and hands the window
/// controller a target size to animate to.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var dashboardTab = "Activity"
    @Published var expanded = false
    @Published private(set) var reminderAlert: NotchReminder?

    /// Mirrors `store.settings.displayPreference`. Owned here (not derived) so
    /// the controller can subscribe to a single source of truth without poking
    /// into the store. The app delegate keeps this in sync both ways: a user
    /// change in Settings flows `store → vm`; on launch the saved value flows
    /// in once. See `NotchFlowApp.applicationDidFinishLaunching`.
    @Published var displayPreference: DisplayPreference = .auto

    let store: Store
    let focus: FocusTimer
    /// Metrics for the fallback screen (used when the preferred screen is not
    /// currently connected, e.g. external unplugged or clamshell). The active
    /// screen is recomputed live via `currentScreen` / `currentMetrics`.
    let metrics: NotchMetrics

    /// Set by the app so dashboard actions can open their full windows.
    var openTasksWindow: () -> Void = {}
    var openMedicationsWindow: () -> Void = {}

    init(store: Store, focus: FocusTimer, metrics: NotchMetrics) {
        self.store = store
        self.focus = focus
        self.metrics = metrics
        startMedicationReminderMonitor()
    }

    // MARK: Layout targets (points)

    /// `NSScreen` the notch should anchor to *right now*. Resolved live from
    /// `displayPreference` against the current `NSScreen.screens`; the captured
    /// `metrics.screen` is the last-resort fallback so a totally broken display
    /// state still produces a sane value.
    var currentScreen: NSScreen {
        DisplayResolver.resolve(displayPreference, fallback: metrics.screen)
    }

    /// `NotchMetrics` derived from `currentScreen`. On screens without a
    /// physical notch (most externals) `NotchMetrics.init` synthesizes a pill
    /// (200pt wide, `safeAreaInsets.top` tall) — that is the historical
    /// behaviour for external displays, preserved here.
    var currentMetrics: NotchMetrics {
        NotchMetrics(screen: currentScreen)
    }

    /// Real hardware notch footprint — content must never sit inside this.
    /// Read from `currentMetrics` so the dimensions follow the screen as the
    /// user switches displays.
    var notchWidth: CGFloat { currentMetrics.notchWidth }
    var notchHeight: CGFloat { currentMetrics.notchHeight }

    /// Width of each "ear" flanking the notch in the collapsed active pill.
    let activeEarWidth: CGFloat = 158

    /// Extra width added on EACH side in minimal mode so the tray's vertical
    /// side segments clear the physical notch edges and stay visible (a pill of
    /// exactly `notchWidth` hides them behind the camera housing).
    let minimalSideMargin: CGFloat = 26

    var collapsedHeight: CGFloat {
        // Keep the dark overhang below the notch small; just enough room for the
        // progress tray to show its bottom + short side segments. With the
        // timeline disabled there's no tray to make room for, so the pill sits
        // flush at the exact hardware-notch height. Minimal mode trims the
        // overhang further so the line hugs the notch's bottom edge.
        let baseHeight: CGFloat
        if focus.isActive && store.settings.showTimeline {
            baseHeight = store.settings.minimalMode ? notchHeight + 8 : notchHeight + 14
        } else {
            baseHeight = notchHeight
        }
        return baseHeight
    }

    /// Fixed height: always exactly two visible to-do rows (the list scrolls if
    /// there are more) alongside the weekday activity grid.
    static let todoRowHeight: CGFloat = 52
    static let visibleTodoRows = 2
    static let todoRowGap: CGFloat = 8
    /// Fixed heights of the dashboard's pieces. The views pin themselves to
    /// these so `expandedHeight` adds up to exactly what they draw; when the
    /// sum came up short the content overflowed the window and the pill's
    /// bottom edge (with the accent line) was cut off.
    static let headerHeight: CGFloat = 22
    static let columnSpacing: CGFloat = 8
    static let addRowHeight: CGFloat = 28
    static let heatmapHeaderSpacing: CGFloat = 10
    static let dashboardTopGap: CGFloat = 4
    static let dashboardTabHeight: CGFloat = 24
    static let dashboardTabSpacing: CGFloat = 8
    static let dashboardBottomPadding: CGFloat = 18

    static var todoListHeight: CGFloat {
        let rows = CGFloat(visibleTodoRows)
        return rows * todoRowHeight + (rows - 1) * todoRowGap
    }

    var expandedHeight: CGFloat {
        let todoColumn = Self.headerHeight + Self.columnSpacing + Self.todoListHeight
            + Self.columnSpacing + Self.addRowHeight
        // Header + only the week-rows the current month needs through today.
        let heatmapColumn = Self.headerHeight + Self.heatmapHeaderSpacing
            + StreakHeatmap.gridHeight(rows: StreakHeatmap.weekRows(for: Date()))
        return notchHeight + Self.dashboardTopGap + Self.dashboardTabHeight
            + Self.dashboardTabSpacing + max(todoColumn, heatmapColumn)
            + Self.dashboardBottomPadding
    }

    var collapsedWidth: CGFloat {
        // Idle: hug the notch exactly (invisible). Active normal: notch + two
        // ears. Active minimal: notch + a small side margin so the tray's side
        // segments clear the notch edges.
        let baseWidth: CGFloat
        if focus.isActive {
            baseWidth = store.settings.minimalMode
                ? notchWidth + minimalSideMargin * 2
                : notchWidth + activeEarWidth * 2
        } else {
            baseWidth = notchWidth
        }
        return baseWidth
    }
    var expandedWidth: CGFloat { 620 }

    var targetSize: CGSize {
        CGSize(width: max(expanded ? expandedWidth : collapsedWidth, reminderAlert == nil ? 0 : 400),
               height: notchContentHeight + (reminderAlert == nil ? 0 : 68))
    }

    var notchContentHeight: CGFloat { expanded ? expandedHeight : collapsedHeight }

    // MARK: Routine reminders

    private func startMedicationReminderMonitor() {
        medicationTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .prepend(Date())
            .sink { [weak self] date in self?.checkReminders(at: date) }
    }

    private func checkReminders(at date: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        if reminderDay != day {
            reminderDay = day
            deliveredMedicationReminderKeys.removeAll()
        }
        let now = calendar.dateComponents([.hour, .minute], from: date)
        for medication in store.medications where medication.isEnabled {
            for time in medication.reminderTimes {
                let clock = calendar.dateComponents([.hour, .minute], from: time)
                let key = "\(medication.id)-\(now.hour ?? 0)-\(now.minute ?? 0)"
                if clock.hour == now.hour, clock.minute == now.minute,
                   deliveredMedicationReminderKeys.insert(key).inserted {
                    reminderQueue.append(.medication(medication))
                }
            }
        }
        // Drop queued or visible reminders when their medication is disabled/deleted.
        reminderQueue.removeAll { !isReminderValid($0, at: date) }
        if let reminderAlert, !isReminderValid(reminderAlert, at: date) {
            dismissReminder()
        }
        let settings = store.hydrationSettings
        let lastDrink = store.waterIntakes.map(\.recordedAt).max() ?? waterReminderBaseline
        let anchor = max(lastDrink, waterReminderBaseline)
        if settings.isReminderDue(at: date, since: anchor, totalMilliliters: store.waterTotal(on: date)),
           reminderAlert != .water, !reminderQueue.contains(.water) {
            reminderQueue.append(.water)
            waterReminderBaseline = date
        }
        presentNextReminder()
    }

    private func isReminderValid(_ reminder: NotchReminder, at date: Date) -> Bool {
        switch reminder {
        case .medication(let medication):
            return store.medications.contains { $0.id == medication.id && $0.isEnabled && $0 == medication }
        case .water:
            return store.hydrationSettings.remindersEnabled
                && store.waterTotal(on: date) < store.hydrationSettings.goalMilliliters
        }
    }

    private func presentNextReminder() {
        guard reminderAlert == nil, !reminderQueue.isEmpty else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            reminderAlert = reminderQueue.removeFirst()
        }
        let task = DispatchWorkItem { [weak self] in self?.dismissReminder() }
        medicationAlertDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: task)
    }

    func dismissReminder() {
        medicationAlertDismissTask?.cancel()
        medicationAlertDismissTask = nil
        if reminderAlert == .water { waterReminderBaseline = Date() }
        withAnimation(.easeOut(duration: 0.2)) { reminderAlert = nil }
        presentNextReminder()
    }

    #if DEBUG
    func debugShowReminder(_ reminder: NotchReminder) {
        medicationTimerCancellable?.cancel()
        reminderAlert = reminder
    }
    #endif

    func confirmReminder() {
        guard let reminderAlert else { return }
        switch reminderAlert {
        case .medication(let medication): store.recordMedicationTaken(medication)
        case .water: store.recordWater()
        }
        dismissReminder()
    }

    // MARK: Hover handling

    /// Delay before collapsing on mouse-exit. Prevents the expand⇄collapse
    /// flicker that happens when the window resizes out from under the cursor.
    private var collapseTask: DispatchWorkItem?
    private var medicationAlertDismissTask: DispatchWorkItem?
    private var medicationTimerCancellable: AnyCancellable?
    private var deliveredMedicationReminderKeys: Set<String> = []
    private var reminderQueue: [NotchReminder] = []
    private var reminderDay: Date?
    private var waterReminderBaseline = Date()

    /// Number of open child windows (popovers, menus) that should keep the
    /// panel expanded. A `.popover` presents in its own window, so moving the
    /// cursor into it fires `.onHover(false)` on the panel — without this the
    /// notch would collapse out from under the popover. Set by `begin/endHold`.
    private var holdCount = 0

    /// Whether the pointer is currently within the panel frame. Wired by the
    /// window controller so we can re-evaluate collapse when a hold ends
    /// (the popover window swallowed the panel's hover events while open).
    var isPointerInside: () -> Bool = { false }

    /// Called from the SwiftUI `.onHover`. Expands immediately, collapses lazily.
    func hover(_ inside: Bool) {
        collapseTask?.cancel()
        collapseTask = nil

        if inside {
            guard reminderAlert == nil, !expanded else { return }
            withAnimation(.easeInEaseOut(duration: 0.24)) { expanded = true }
        } else {
            scheduleCollapse()
        }
    }

    /// Keep the panel expanded while a popover/menu is open. Balanced by `endHold`.
    func beginHold() {
        holdCount += 1
        collapseTask?.cancel()
        collapseTask = nil
    }

    /// Release a hold. If nothing else holds the panel open and the pointer has
    /// left the panel, collapse lazily — mirroring a normal mouse-exit.
    func endHold() {
        holdCount = max(0, holdCount - 1)
        guard holdCount == 0, !isPointerInside() else { return }
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        guard holdCount == 0 else { return }   // held open by a popover/menu
        collapseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.expanded, self.holdCount == 0,
                  !self.isPointerInside() else { return }
            withAnimation(.easeInEaseOut(duration: 0.24)) { self.expanded = false }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }
}

private extension Animation {
    static func easeInEaseOut(duration: Double) -> Animation { .easeInOut(duration: duration) }
}
