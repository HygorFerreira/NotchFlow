import SwiftUI
import Combine
import EventKit

enum NotchReminder: Equatable {
    case medication(Medication)
    case water
    case routineBreak(RoutineBreak)
}

/// Drives the notch panel's collapsed ⇄ expanded state and hands the window
/// controller a target size to animate to.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var dashboardTab = "Activity"
    @Published private(set) var upcomingEvent: UpcomingEvent?
    @Published private(set) var compactEvent: UpcomingEvent?
    @Published private(set) var calendarAuthorized = false
    @Published var expanded = false
    @Published var musicPeek = false
    @Published private(set) var reminderAlert: NotchReminder?

    /// Mirrors `store.settings.displayPreference`. Owned here (not derived) so
    /// the controller can subscribe to a single source of truth without poking
    /// into the store. The app delegate keeps this in sync both ways: a user
    /// change in Settings flows `store → vm`; on launch the saved value flows
    /// in once. See `NotchFlowApp.applicationDidFinishLaunching`.
    @Published var displayPreference: DisplayPreference = .auto

    let store: Store
    let focus: FocusTimer
    let music: MusicMonitor
    let tools: ToolsModel
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
        #if DEBUG
        music = MusicMonitor(start: !Snapshots.isRequested)
        tools = ToolsModel(isolated: Snapshots.isRequested)
        #else
        music = MusicMonitor()
        tools = ToolsModel()
        #endif
        music.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            if self.music.playback == nil { self.musicPeek = false }
            self.objectWillChange.send()
        }.store(in: &routineCancellables)
        refreshCalendar(at: Date())
        startMedicationReminderMonitor()
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCalendar(at: Date()) }
            .store(in: &routineCancellables)
        store.$settings.receive(on: RunLoop.main).sink { [weak self] settings in
            guard let self else { return }
            let modules = DashboardModule.normalized(settings.dashboardModules)
            if !modules.contains(self.dashboardTab) { self.dashboardTab = modules[0] }
            self.checkReminders(at: Date())
        }.store(in: &routineCancellables)
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
    let activeEarWidth: CGFloat = 110

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
            baseHeight = notchHeight + 8
        } else {
            baseHeight = notchHeight
        }
        return baseHeight
    }

    /// Fixed height: always exactly two visible to-do rows (the list scrolls if
    /// there are more) alongside the weekday activity grid.
    static let todoRowHeight: CGFloat = 62
    static let visibleTodoRows = 2
    static let todoRowGap: CGFloat = 8
    /// Fixed heights of the dashboard's pieces. The views pin themselves to
    /// these so `expandedHeight` adds up to exactly what they draw; when the
    /// sum came up short the content overflowed the window and the pill's
    /// bottom edge (with the accent line) was cut off.
    static let headerHeight: CGFloat = 22
    static let columnSpacing: CGFloat = 8
    static let addRowHeight: CGFloat = 42
    static let heatmapHeaderSpacing: CGFloat = 10
    static let dashboardTopGap: CGFloat = 22
    static let dashboardTabHeight: CGFloat = 30
    static let dashboardTabSpacing: CGFloat = 14
    static let dashboardBottomPadding: CGFloat = 20
    static let musicPeekHeight: CGFloat = 82

    static var todoListHeight: CGFloat {
        let rows = CGFloat(visibleTodoRows)
        return rows * todoRowHeight + (rows - 1) * todoRowGap
    }

    var expandedHeight: CGFloat {
        let todoColumn = Self.todoListHeight + Self.columnSpacing + Self.addRowHeight
        // Header + only the week-rows the current month needs through today.
        let heatmapColumn = Self.headerHeight + Self.heatmapHeaderSpacing
            + StreakHeatmap.gridHeight(rows: StreakHeatmap.weekRows(for: Date()))
        let contentHeight = dashboardTab == "Health"
            ? max(todoColumn + Self.headerHeight + Self.columnSpacing, heatmapColumn)
            : max(todoColumn, 178)
        let extra: CGFloat = dashboardTab == "Music" ? (music.enabled ? 210 : 30) : dashboardTab == "Tools" ? 45 : dashboardTab == "Activity" ? 48 : dashboardTab == "Health" ? 72 : dashboardTab == "Machine" ? 36 : 0
        return extra + notchHeight + Self.dashboardTopGap + Self.dashboardTabHeight + 6
            + Self.dashboardTabSpacing + contentHeight
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
            baseWidth = music.hasActivity ? notchWidth + activeEarWidth * 2 : notchWidth
        }
        if musicPeek { return max(500, baseWidth) }
        let activeWidth = music.hasActivity && focus.isActive && !store.settings.minimalMode ? baseWidth + 48 : baseWidth
        return max(activeWidth, compactEvent == nil ? 0 : 480)
    }
    var expandedWidth: CGFloat { 700 }

    var targetSize: CGSize {
        CGSize(width: max(expanded ? expandedWidth : collapsedWidth, reminderAlert == nil ? 0 : 400),
               height: notchContentHeight + (reminderAlert == nil ? 0 : 68))
    }

    var notchContentHeight: CGFloat { expanded ? expandedHeight : collapsedHeight + (musicPeek ? Self.musicPeekHeight : 0) + (compactEvent == nil ? 0 : 42) }

    func openTools(_ section: ToolsSection = .notes) {
        if !store.settings.dashboardModules.contains("Tools") { store.settings.dashboardModules.append("Tools") }
        tools.section = section
        dashboardTab = "Tools"
        musicPeek = false
        withAnimation(.easeInOut(duration: 0.24)) { expanded = true }
    }

    func openMusic() {
        if !store.settings.dashboardModules.contains("Music") { store.settings.dashboardModules.append("Music") }
        dashboardTab = "Music"
        musicPeek = false
        withAnimation(.easeInOut(duration: 0.24)) { expanded = true }
    }

    // MARK: Routine reminders

    private func startMedicationReminderMonitor() {
        medicationTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .prepend(Date())
            .sink { [weak self] date in self?.checkReminders(at: date) }
    }

    private func checkReminders(at date: Date) {
        if date.timeIntervalSince(lastCalendarRefresh) >= 30 { refreshCalendar(at: date) }
        let next = calendarCandidates.first { $0.isCompactDue(at: date, enabled: store.settings.upcomingEventEnabled,
            leadMinutes: store.settings.upcomingEventLeadMinutes) }
        if compactEvent != next { compactEvent = next }
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
        for kind in RoutineBreak.allCases {
            var schedule = breakSchedules[kind] ?? BreakSchedule()
            let enabled = kind == .eyes ? store.settings.eyeBreaksEnabled : store.settings.postureBreaksEnabled
            let minutes = kind == .eyes ? store.settings.eyeBreakMinutes : store.settings.postureBreakMinutes
            schedule.update(enabled: enabled, minutes: minutes, now: date)
            if schedule.isDue(at: date), reminderAlert != .routineBreak(kind), !reminderQueue.contains(.routineBreak(kind)) {
                reminderQueue.append(.routineBreak(kind))
                schedule.deferUntil(date)
            }
            breakSchedules[kind] = schedule
        }
        presentNextReminder()
    }

    private func isReminderValid(_ reminder: NotchReminder, at date: Date) -> Bool {
        switch reminder {
        case .medication(let medication):
            return store.medications.contains { $0.id == medication.id && $0.isEnabled && $0 == medication }
        case .routineBreak(let kind):
            return kind == .eyes ? store.settings.eyeBreaksEnabled : store.settings.postureBreaksEnabled
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
        if case .routineBreak(let kind) = reminderAlert { breakSchedules[kind]?.deferUntil(Date()) }
        withAnimation(.easeOut(duration: 0.2)) { reminderAlert = nil }
        presentNextReminder()
    }

    #if DEBUG
    func debugSetUpcomingEvent(_ event: UpcomingEvent?) {
        upcomingEvent = event
        calendarCandidates = event.map { [$0] } ?? []
        calendarAuthorized = true
        compactEvent = event.flatMap { $0.isCompactDue(at: Date(), enabled: store.settings.upcomingEventEnabled,
            leadMinutes: store.settings.upcomingEventLeadMinutes) ? $0 : nil }
    }

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
        case .routineBreak: break
        }
        dismissReminder()
    }

    func snoozeBreak() {
        guard case .routineBreak(let kind) = reminderAlert else { return }
        dismissReminder()
        breakSchedules[kind]?.deferUntil(Date(), minutes: 5)
    }

    private var lastCalendarRefresh = Date.distantPast
    private var calendarCandidates: [UpcomingEvent] = []
    private var routineCancellables = Set<AnyCancellable>()
    private var breakSchedules: [RoutineBreak: BreakSchedule] = [:]

    private func refreshCalendar(at now: Date) {
        #if DEBUG
        guard !Snapshots.isRequested else { return }
        #endif
        lastCalendarRefresh = now
        calendarAuthorized = CalendarService.shared.authState() == .authorized
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let events = CalendarService.shared.events(on: now) + CalendarService.shared.events(on: tomorrow)
        calendarCandidates = events.filter { event in
            !event.isAllDay && event.endDate > now && event.status != .canceled
                && !(event.attendees ?? []).contains(where: { $0.isCurrentUser && $0.participantStatus == .declined })
        }.sorted { $0.startDate < $1.startDate }.map { event in
            UpcomingEvent(title: event.title ?? String(localized: "Calendar event"), start: event.startDate,
                          end: event.endDate, meetingURL: UpcomingEvent.meetingLink(in:
                            [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: "\n")))
        }
        upcomingEvent = calendarCandidates.first
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
            withAnimation(.easeInEaseOut(duration: 0.24)) {
                if music.hasActivity { musicPeek = true }
                else { expanded = true }
            }
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
            guard let self, (self.expanded || self.musicPeek), self.holdCount == 0,
                  !self.isPointerInside() else { return }
            withAnimation(.easeInEaseOut(duration: 0.24)) { self.expanded = false; self.musicPeek = false }
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }
}

private extension Animation {
    static func easeInEaseOut(duration: Double) -> Animation { .easeInOut(duration: duration) }
}
