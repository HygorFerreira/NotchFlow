import SwiftUI

/// Expanded hover panel: To-Do list on the left, streak heatmap on the right.
struct NotchDashboardView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedTab: DashboardTab {
        get { DashboardTab(rawValue: vm.dashboardTab) ?? .activity }
        nonmutating set { vm.dashboardTab = newValue.rawValue }
    }

    private enum DashboardTab: String, CaseIterable, Identifiable {
        case activity = "Activity"
        case health = "Health"
        case machine = "Machine"
        case water = "Water"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .activity: return "checklist"
            case .health: return "heart.fill"
            case .machine: return "desktopcomputer"
            case .water: return "drop.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: NotchViewModel.dashboardTabSpacing) {
            tabBar

            Group {
                switch selectedTab {
                case .activity:
                    activityDashboard
                case .health:
                    HealthDashboardView()
                case .machine:
                    MachineDashboardView()
                case .water:
                    WaterDashboardView()
                }
            }
        }
        .padding(.horizontal, 18)
        // Clear the physical notch: content starts below the notch height.
        .padding(.top, vm.notchHeight + NotchViewModel.dashboardTopGap)
        .padding(.bottom, NotchViewModel.dashboardBottomPadding)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Label(tab.rawValue.localized, systemImage: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: NotchViewModel.dashboardTabHeight)
                        .background(
                            selectedTab == tab ? Theme.accent.opacity(0.22) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var activityDashboard: some View {
        HStack(alignment: .top, spacing: 16) {
            TodoPanel()
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)

            StreakHeatmap()
                .frame(width: 204, alignment: .topLeading)
        }
    }
}

/// Left panel — task list with per-row start/stop + "Add a task".
struct TodoPanel: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer

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
            HStack {
                TaskFiltersView(compact: true)
                Spacer()
                Button { vm.openTasksWindow() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: NotchViewModel.headerHeight)

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
                        .animation(.spring(response: 0.28, dampingFraction: 0.85),
                                   value: targetIndex())
                        .animation(.easeOut(duration: 0.12), value: draggingFrom)
                    }
                }
            }
            .frame(height: NotchViewModel.todoListHeight)

            HStack(spacing: 12) {
                Button { vm.openTasksWindow() } label: {
                    Label("Add a task", systemImage: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: NotchViewModel.addRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { vm.openMedicationsWindow() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pills.fill")
                        Text(nextMedicationLabel)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.medication)
                    .frame(height: NotchViewModel.addRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open medication reminders")
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

    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer

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

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                if let start = task.scheduledStart {
                    HStack(spacing: 3) {
                        Text(start.formatted(date: .omitted, time: .shortened))
                        if task.reminderMinutesBefore != nil { Image(systemName: "bell") }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                }
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
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
                onPopoverChange: { shown in shown ? vm.beginHold() : vm.endHold() }
            )

            Button {
                if isRunningThis { focus.togglePause() } else { focus.start(task: task) }
            } label: {
                Image(systemName: isRunningThis && focus.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .background(isRunningThis && focus.state == .running ? Theme.danger : Theme.accent,
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
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging { onDragStart() }
                            onDragChanged(value.translation.height)
                        }
                        .onEnded { _ in onDragEnd() }
                )
        }
        .padding(.horizontal, 8)
        .frame(height: NotchViewModel.todoRowHeight)
        .background(isDragging ? Theme.panelHover : Theme.panel,
                    in: RoundedRectangle(cornerRadius: Theme.panelCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelCorner)
            .strokeBorder(isRunningThis ? Theme.accent.opacity(0.6) : Color.white.opacity(0.06)))
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .opacity(task.isDone ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: task.isDone)
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
