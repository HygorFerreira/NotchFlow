import SwiftUI
import EventKit

/// The big window: month calendar on the left, the selected day's tasks on the
/// right with a Day / Unscheduled toggle and an inline add-task form.
struct TasksWindowView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer
    @StateObject private var calendar = CalendarAuthModel()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedDate = Date()
    @State private var tab: Tab = .day
    @State private var showAddForm = false
    @State private var showCalendar = false
    @State private var draftTitle = ""
    @State private var draftNotes = ""
    @State private var draftProject = ""
    @State private var draftTags = ""
    @State private var draftRecurrence = TaskRecurrence()
    @State private var draftStartTime: Date?
    @State private var draftReminderMinutesBefore: Int?
    @State private var editingTask: Task?

    // Focus management for the add-task form. Set to true when the form
    // appears so the user can start typing the title without a second click.
    @FocusState private var titleFocused: Bool

    // Custom drag bookkeeping — same shape as the notch so a reorder feels
    // consistent in both surfaces. `listedTasks` is the filtered+sorted
    // array the user is looking at, and `targetIndex` is where the dragged
    // row would land if released right now.
    @State private var draggingFrom: Int?
    @State private var dragOffset: CGFloat = 0
    private let rowGap: CGFloat = 8
    private let rowHeight: CGFloat = 60

    enum Tab: String, CaseIterable { case day = "Day", unscheduled = "Unscheduled" }

    /// Days with unfinished tasks, for the dots in the month grid.
    private var busyDays: Set<Date> {
        let cal = Calendar.current
        return Set(store.tasks.lazy.filter { !$0.isDone }.compactMap { $0.scheduledDate.map(cal.startOfDay) })
    }

    private var listedTasks: [Task] {
        let tasks = store.filteredTasks(tab == .day ? store.tasks(on: selectedDate) : store.unscheduled)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? tasks : tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
                || $0.organizationLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ---- Left: calendar ----
            VStack(spacing: 12) {
                HStack {
                    Label("NotchFlow", systemImage: "waveform.path")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button { AppDelegate.shared?.showSettingsWindow() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel(Text("Settings"))
                }
                CalendarView(selectedDate: $selectedDate, busyDays: busyDays)
                    .padding(12)
                    .flowSurface()
                Text("YOUR SPACE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                FlowNavigationRow(title: "Weekly summary", symbol: "chart.bar", color: .purple) {
                    AppDelegate.shared?.showWeeklySummaryWindow()
                }
                FlowNavigationRow(title: "Medications", symbol: "pills.fill", color: Theme.medication) {
                    AppDelegate.shared?.showMedicationsWindow()
                }
                FlowNavigationRow(title: "Water", symbol: "drop.fill", color: .cyan) {
                    AppDelegate.shared?.showWaterWindow()
                }
                Spacer()
                Button("Today") { selectedDate = Date(); tab = .day }
                    .keyboardShortcut("t")
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .padding(20)
            .frame(width: 290)
            .background { FlowBackdrop(shape: Rectangle(), color: Theme.sidebar) }

            Divider()

            // ---- Right: the day's task list ----
            todoPanel
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 840, minHeight: 600)
        .background(Theme.windowBackground)
        .flowAppearance()
        .sheet(isPresented: $showAddForm) { addForm }
        .sheet(item: $editingTask) { task in
            TaskDetailView(task: task)
                .environmentObject(store)
                .environmentObject(focus)
        }
        .onAppear {
            consumePendingOpen()
            calendar.refresh(for: selectedDate)
        }
        .onChange(of: store.pendingOpenTaskID) { _, _ in consumePendingOpen() }
        .onChange(of: selectedDate) { _, newDate in calendar.refresh(for: newDate) }
        .onChange(of: tab) { _, newTab in
            if newTab == .unscheduled { draftStartTime = nil; draftReminderMinutesBefore = nil }
        }
    }

    /// The task list: inner Day/Unscheduled toggle, the drag-to-reorder list,
    /// the calendar event feed, and the inline add form.
    @ViewBuilder private var todoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab == .day ? headerTitle : String(localized: "Unscheduled"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if tab == .day {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue.localized).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()
            }

            taskProgress

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Search tasks", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 12))
            .padding(11)
            .flowSurface()
            .background {
                Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            }
            TaskFiltersView()
            TaskReminderStatusView()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: rowGap) {
                    if listedTasks.isEmpty {
                        emptyState
                    }
                    ForEach(Array(listedTasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            index: index,
                            isDragging: draggingFrom == index,
                            onDragStart: { handleDragStart(index) },
                            onDragChanged: { handleDragChanged($0) },
                            onDragEnd: handleDragEnd,
                            onOpen: { editingTask = task }
                        )
                        .offset(y: offsetForIndex(index))
                        .opacity(draggingFrom != nil && draggingFrom != index ? 0.45 : 1.0)
                        .zIndex(draggingFrom == index ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85),
                                   value: targetIndex())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: draggingFrom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if tab == .day {
                DisclosureGroup(isExpanded: $showCalendar) {
                    calendarSection.padding(.top, 8)
                } label: {
                    Label("Calendar events", systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !showAddForm {
                Button {
                    withAnimation { showAddForm = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add a task")
                            .font(.system(size: 13))
                        Spacer()
                        Text("⌘N")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.45)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(FlowCompactButtonStyle())
                .keyboardShortcut("n")
            }
        }
    }

    private var hasFilters: Bool {
        store.selectedProject != nil || store.selectedTag != nil || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var taskProgress: some View {
        let completed = listedTasks.filter(\.isDone).count
        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text("\(completed) of \(listedTasks.count) completed")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .accessibilityLabel(Text("Completed tasks"))
                    .accessibilityValue("\(completed) / \(listedTasks.count)")
                FlowProgressBar(value: Double(completed) / Double(max(listedTasks.count, 1)))
            }
            Spacer(minLength: 8)
            Text("\(listedTasks.filter { !$0.isDone }.reduce(0) { $0 + $1.estimateMinutes }) min")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .help("Estimated focus time")
        }
        .padding(14)
        .flowSurface()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle" : "checklist")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
            Text(hasFilters ? String(localized: "No tasks match this view") : String(localized: "No tasks yet"))
                .font(.system(size: 16, weight: .semibold))
            Text(hasFilters ? String(localized: "Clear search and filters to see your tasks.") : String(localized: "Add a task to plan your next focus session."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if hasFilters {
                Button("Reset view") {
                    search = ""
                    store.selectedProject = nil
                    store.selectedTag = nil
                }
                .buttonStyle(FlowButtonStyle())
            } else {
                Button("Add a task") { withAnimation { showAddForm = true } }
                    .buttonStyle(FlowButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Calendar section

    @ViewBuilder private var calendarSection: some View {
        switch calendar.state {
        case .notDetermined:
            calendarBanner(
                icon: "calendar.badge.plus",
                title: "Show today's calendar events",
                detail: "NotchFlow only reads your events and never changes them.",
                action: "Connect calendar"
            ) {
                _Concurrency.Task { await calendar.requestAccess() }
            }
        case .denied, .restricted:
            calendarBanner(
                icon: "calendar.badge.exclamationmark",
                title: "Calendar access denied",
                detail: "Open System Settings › Privacy & Security › Calendars to grant access.",
                action: "Open System Settings"
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .authorized:
            if !calendar.events.isEmpty {
                ScrollView { eventsList }
                    .frame(height: min(150, CGFloat(calendar.events.count) * 28 + 26))
            }
        }
    }

    private func calendarBanner(icon: String,
                                title: String,
                                detail: String,
                                action: String,
                                perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.localized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail.localized)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Button(action.localized) { perform() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var eventsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(calendar.events.count) events")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 4) {
                ForEach(calendar.events, id: \.eventIdentifier) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 6, height: 6)
            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(event.title ?? String(localized: "Untitled event"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Open the detail sheet when the dashboard requested a specific task.
    private func consumePendingOpen() {
        guard let id = store.pendingOpenTaskID,
              let task = store.tasks.first(where: { $0.id == id }) else { return }
        editingTask = task
        store.pendingOpenTaskID = nil
    }

    private var headerTitle: String {
        Calendar.current.isDateInToday(selectedDate)
            ? String(localized: "Today") : selectedDate.formatted(.dateTime.month().day())
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowPageHeading(title: "New task", subtitle: "One clear next step", symbol: "plus.square")
                .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Task title", text: $draftTitle)
                        .textFieldStyle(FlowTextFieldStyle())
                        .focused($titleFocused)
                        .onChange(of: draftTitle) { _, value in draftTitle = String(value.prefix(Task.titleLimit)) }
                    TextField("Notes (optional)", text: $draftNotes, axis: .vertical)
                        .lineLimit(3...5)
                        .textFieldStyle(FlowTextFieldStyle())
                        .onChange(of: draftNotes) { _, value in draftNotes = String(value.prefix(Task.notesLimit)) }
                    TaskScheduleView(date: Binding(
                        get: { tab == .day ? selectedDate : nil },
                        set: { value in if let value { selectedDate = value; tab = .day } }),
                        startTime: $draftStartTime, reminderMinutesBefore: $draftReminderMinutesBefore)
                    TaskOptionsView(project: $draftProject, tagsText: $draftTags, recurrence: $draftRecurrence)
                    HStack {
                        counter("Title", draftTitle.count, Task.titleLimit)
                        Spacer()
                        counter("Notes", draftNotes.count, Task.notesLimit)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text(tab == .day ? headerTitle : String(localized: "Unscheduled"))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Cancel") { resetDraft() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(FlowButtonStyle())
                Button("Add a task") { commitDraft() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(FlowButtonStyle(prominent: true))
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftRecurrence.isValid)
            }
            .padding(20)
        }
        .frame(width: 500, height: 570)
        .background(Theme.windowBackground)
        .flowAppearance()
        .onAppear { titleFocused = true }
    }

    private func counter(_ label: String, _ count: Int, _ limit: Int) -> some View {
        Text("\(label.localized) \(count)/\(limit)")
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(count >= limit ? Theme.accent : Theme.textSecondary)
    }

    private func commitDraft() {
        guard !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draftRecurrence.isValid else { return }
        store.add(title: draftTitle, notes: draftNotes,
                  date: tab == .day ? selectedDate : nil,
                  project: draftProject, tags: Task.normalizedTags(draftTags), recurrence: draftRecurrence,
                  startTime: draftStartTime, reminderMinutesBefore: draftReminderMinutesBefore)
        // A newly created task should be visible even when filters were active.
        store.selectedProject = nil
        store.selectedTag = nil
        search = ""
        resetDraft()
    }

    private func resetDraft() {
        draftTitle = ""; draftNotes = ""
        draftProject = ""; draftTags = ""; draftRecurrence = TaskRecurrence()
        draftStartTime = nil; draftReminderMinutesBefore = nil
        withAnimation { showAddForm = false }
    }

    // MARK: - Custom drag bookkeeping (mirrors the notch panel)

    private func handleDragStart(_ index: Int) {
        draggingFrom = index
        dragOffset = 0
    }

    private func handleDragChanged(_ offset: CGFloat) {
        dragOffset = offset
    }

    private func handleDragEnd() {
        if let from = draggingFrom {
            let to = targetIndex()
            if to != from {
                // `move(toOffset:)` inserts *before* the given offset, so a
                // downward move needs +1 to actually land past its new
                // neighbor (otherwise it stops one slot short of the bottom).
                let dest = to > from ? to + 1 : to
                store.moveTasks(in: listedTasks, from: IndexSet(integer: from), to: dest)
            }
        }
        draggingFrom = nil
        dragOffset = 0
    }

    private func targetIndex() -> Int {
        guard let from = draggingFrom else { return 0 }
        let total = listedTasks.count
        guard total > 0 else { return 0 }
        let stride = rowHeight + rowGap
        // Center-based: the row whose center is closest to the dragged row's
        // center wins. No half-stride rounding flicker — the target only
        // flips when the dragged row's center actually crosses a neighbor's.
        let draggedCenter = CGFloat(from) * stride + rowHeight / 2 + dragOffset
        var best = from
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0..<total {
            let center = CGFloat(i) * stride + rowHeight / 2
            let d = abs(draggedCenter - center)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    private func offsetForIndex(_ index: Int) -> CGFloat {
        guard let from = draggingFrom else { return 0 }
        if index == from { return dragOffset }
        let target = targetIndex()
        let stride = rowHeight + rowGap
        if target > from, index > from, index <= target { return -stride }
        if target < from, index < from, index >= target { return stride }
        return 0
    }
}
