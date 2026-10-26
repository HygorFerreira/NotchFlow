import SwiftUI

/// Compact navigation above the dashboard, with task and activity columns.
struct NotchDashboardView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFilters = false
    @State private var showMachineOptions = false
    private var selectedTab: DashboardTab {
        get { visibleTabs.first(where: { $0.rawValue == vm.dashboardTab }) ?? visibleTabs[0] }
        nonmutating set { vm.dashboardTab = newValue.rawValue }
    }

    private typealias DashboardTab = DashboardModule
    private var visibleTabs: [DashboardModule] {
        DashboardModule.normalized(vm.store.settings.dashboardModules).compactMap(DashboardModule.init(rawValue:))
    }

    var body: some View {
        VStack(spacing: NotchViewModel.dashboardTabSpacing) {
            tabBar
                .frame(width: 370)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Button(action: headerAction) {
                        Image(systemName: selectedTab == .activity ? "line.3.horizontal.decrease" : "slider.horizontal.3")
                            .font(.system(size: 11))
                            .foregroundStyle(NotchPalette.secondary)
                            .frame(width: 26, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help(headerActionTitle)
                    .accessibilityLabel(Text(headerActionTitle))
                    .popover(isPresented: $showMachineOptions) {
                        KeepAwakeControl().padding(16).frame(width: 330)
                    }
                    .popover(isPresented: $showFilters) {
                        TaskFiltersView(compact: true).padding(16)
                            .environmentObject(vm.store)
                    }
                }

            Group {
                switch selectedTab {
                case .activity:
                    activityDashboard
                case .health:
                    HealthDashboardView()
                case .machine:
                    MachineDashboardView(onPopoverChange: { shown in shown ? vm.beginHold() : vm.endHold() })
                case .water:
                    WaterDashboardView()
                case .ai:
                    AIUsageDashboardView()
                }
            }
        }
        .padding(.horizontal, 20)
        // Clear the physical notch: content starts below the notch height.
        .padding(.top, vm.notchHeight + NotchViewModel.dashboardTopGap)
        .padding(.bottom, NotchViewModel.dashboardBottomPadding)
        .onChange(of: showMachineOptions) { _, shown in
            shown ? vm.beginHold() : vm.endHold()
        }
        .onChange(of: showFilters) { _, shown in
            shown ? vm.beginHold() : vm.endHold()
        }
    }

    private var headerActionTitle: String {
        switch selectedTab {
        case .activity: return String(localized: "Projects")
        case .ai: return String(localized: "Connect AI services")
        case .health: return String(localized: "Health settings")
        case .water: return String(localized: "Water settings")
        case .machine: return String(localized: "Machine settings")
        }
    }

    private func headerAction() {
        switch selectedTab {
        case .activity: showFilters.toggle()
        case .ai: AppDelegate.shared?.showAIUsageWindow()
        case .water: AppDelegate.shared?.showWaterWindow()
        case .health: AppDelegate.shared?.showSettingsWindow(.focus)
        case .machine: showMachineOptions.toggle()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue.localized)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? Color(hex: "#24262C") : NotchPalette.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: NotchViewModel.dashboardTabHeight)
                        .background(selectedTab == tab ? Color(hex: "#E8EBF3") : .clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowCompactButtonStyle())
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity")
    }

    private var activityDashboard: some View {
        VStack(spacing: 8) {
            UpcomingEventRow()
            HStack(alignment: .top, spacing: 16) {
                TodoPanel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)

                FocusActivityHeatmap()
                    .frame(width: 244, height: NotchViewModel.todoListHeight + NotchViewModel.columnSpacing + NotchViewModel.addRowHeight, alignment: .topLeading)
            }
        }
    }
}

/// Left panel — task list with per-row start/stop + "Add a task".
struct TodoPanel: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingFrom: Int?
    @State private var dragOffset: CGFloat = 0

    private let rowHeight = NotchViewModel.todoRowHeight
    private let rowGap = NotchViewModel.todoRowGap

    /// Today's tasks with done ones sorted to the bottom (Store.isBefore
    /// handles that). We keep completed tasks visible so checking one off
    /// doesn't make it vanish — it just sinks.
    private var todays: [Task] { store.filteredTasks(store.tasks(on: Date())) }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchViewModel.columnSpacing) {
            // Exactly two rows tall; scrolls when there are more tasks.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: rowGap) {
                    if todays.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "checklist").foregroundStyle(Theme.accent)
                            Text("Your day starts here").font(.system(size: 12, weight: .semibold))
                            Text("Add a task to begin").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: NotchViewModel.todoListHeight)
                    }
                    ForEach(Array(todays.enumerated()), id: \.element.id) { index, task in
                        TodoRow(
                            task: task,
                            index: index,
                            isDragging: draggingFrom == index,
                            onDragStart: { handleDragStart(index) },
                            onDragChanged: { handleDragChanged($0) },
                            onDragEnd: handleDragEnd
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
            .frame(height: NotchViewModel.todoListHeight)

            HStack(spacing: 6) {
                Button { vm.openTasksWindow() } label: {
                    Label("Add a task", systemImage: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: NotchViewModel.addRowHeight)
                        .padding(.horizontal, 14)
                        .background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NotchPalette.border))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { vm.openMedicationsWindow() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pills.fill")
                        Text(nextMedicationLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 8))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchPalette.text)
                    .frame(height: NotchViewModel.addRowHeight)
                    .padding(.horizontal, 12)
                    .background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NotchPalette.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open medication reminders")
                .accessibilityLabel("Open medication reminders")
            }
        }
    }

    private var nextMedicationLabel: String {
        guard let reminder = store.nextMedicationReminder() else {
            return String(localized: "Medications")
        }
        return String(
            localized: "Next \(reminder.date.formatted(date: .omitted, time: .shortened))"
        )
    }

    // MARK: - Custom drag bookkeeping

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
                store.moveTasks(in: todays, from: IndexSet(integer: from), to: dest)
            }
        }
        draggingFrom = nil
        dragOffset = 0
    }

    /// Where the dragged row would land if released right now.
    private func targetIndex() -> Int {
        guard let from = draggingFrom else { return 0 }
        let total = todays.count
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

    /// Per-row vertical offset: dragged row tracks the cursor, the rows
    /// between `from` and `target` shift one stride to make space.
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

private struct TodoRow: View {
    let task: Task
    let index: Int
    let isDragging: Bool
    let onDragStart: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer
    @State private var hovered = false

    private var isRunningThis: Bool {
        focus.isActive && focus.activeTask?.id == task.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { store.toggleDone(task) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.isDone ? Theme.accent : Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(task.isDone ? String(localized: "Mark as incomplete") : String(localized: "Mark as complete")))

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                if isRunningThis { FlowFocusBadge() }
                if !isRunningThis, let schedule = task.scheduleLabel {
                    HStack(spacing: 3) {
                        Text(schedule)
                        if task.reminderMinutesBefore != nil { Image(systemName: "bell") }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                }

            }
            .contentShape(Rectangle())
            .onTapGesture {
                store.pendingOpenTaskID = task.id
                vm.openTasksWindow()
            }
            Spacer(minLength: 6)

            // Inline time editor — tap to change the estimate without opening
            // the full task form. Six presets keep the popover from clipping
            // the last chip (it has to fit a compact popover on the notch).
            FocusTimePicker(
                minutes: estimateBinding,
                range: FocusSettings.focusRange,
                presets: [10, 15, 25, 30, 45, 60],
                compact: true,
                onPopoverChange: { shown in shown ? vm.beginHold() : vm.endHold() }
            )

            Button {
                if isRunningThis { focus.togglePause() } else { focus.start(task: task) }
            } label: {
                Image(systemName: isRunningThis && focus.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .background(isRunningThis || (index == 0 && !focus.isActive) ? NotchPalette.accent : Color(hex: "#40444D"),
                                in: Circle())
            }
            .buttonStyle(.plain)

            .disabled(task.isDone)
            .help(isRunningThis ? String(localized: "Pause or resume focus") : String(localized: "Start focus"))

            // Drag handle — six dots in a 2×3 grid. Only this corner is
            // draggable; the rest of the row keeps its tap-to-open behavior.
            // minimumDistance: 3 keeps a stray click from flashing the row.
            // .global space: the row is moved by `.offset(y:)` mid-drag, so a
            // .local space would feed the translation back into itself.
            DragHandle()
                .scaleEffect(0.7)
                .frame(width: 8)
                .opacity(hovered || isDragging ? 0.8 : 0)
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging { onDragStart() }
                            onDragChanged(value.translation.height)
                        }
                        .onEnded { _ in onDragEnd() }
                )
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: NotchViewModel.todoRowHeight)
        .background(isDragging || hovered ? NotchPalette.cardHover : NotchPalette.card,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(isRunningThis ? Theme.accent.opacity(0.35) : NotchPalette.border))
        .onHover { hovered = $0 }
        .scaleEffect(isDragging && !reduceMotion ? 1.03 : 1.0)
        .opacity(task.isDone ? 0.5 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: task.isDone)
    }

    /// Two-way binding into the store for the inline time picker.
    private var estimateBinding: Binding<Int> {
        Binding(
            get: { task.estimateMinutes },
            set: { newValue in
                var updated = task
                updated.estimateMinutes = newValue
                store.update(updated)
            }
        )
    }
}
