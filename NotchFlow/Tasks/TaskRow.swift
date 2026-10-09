import SwiftUI

/// A row in the Tasks window: checkbox, title, estimate, and
/// start / delete controls. Tapping the row opens the task's detail sheet.
/// Drag handle in the corner is the only draggable area.
struct TaskRow: View {
    let task: Task
    let index: Int
    let isDragging: Bool
    let onDragStart: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnd: () -> Void
    var onOpen: () -> Void = {}

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer

    @State private var isHovered = false

    private var isRunningThis: Bool { focus.isActive && focus.activeTask?.id == task.id }

    var body: some View {
        HStack(spacing: 10) {
            Button { store.toggleDone(task) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.isDone ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isDone ? String(localized: "Mark as incomplete") : String(localized: "Mark as complete"))
            .accessibilityLabel(Text(task.isDone ? String(localized: "Mark as incomplete") : String(localized: "Mark as complete")))

            Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                    .help(task.title)
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if !task.organizationLabel.isEmpty || task.recurrence.frequency != .none || task.scheduledStart != nil {
                    HStack(spacing: 4) {
                        if task.recurrence.frequency != .none { Image(systemName: "repeat") }
                        if let start = task.scheduledStart {
                            Text(start.formatted(date: .omitted, time: .shortened))
                            if task.reminderMinutesBefore != nil { Image(systemName: "bell") }
                        }
                        Text(task.organizationLabel)
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open task details")

            Spacer(minLength: 8)

            // Inline time editor — tapping opens the popover, changes persist
            // back to the store immediately. Six presets keep the popover
            // from clipping the last chip.
            FocusTimePicker(
                minutes: estimateBinding,
                range: FocusSettings.focusRange,
                presets: [10, 15, 25, 30, 45, 60]
            )

            iconButton(isRunningThis && focus.state == .running ? "pause.fill" : "play.fill",
                       bg: isRunningThis && focus.state == .running ? Theme.danger : Theme.accent) {
                if isRunningThis { focus.togglePause() } else { focus.start(task: task) }
            }
            .disabled(task.isDone)
            .help(isRunningThis ? (focus.state == .running ? String(localized: "Pause") : String(localized: "Resume")) : String(localized: "Start focus"))
            iconButton("trash", bg: .clear, fg: Theme.textSecondary) { store.delete(task) }
                .help("Delete task")

            // Drag handle — six dots in a 2×3 grid. Only this corner drags;
            // minimumDistance: 3 keeps a stray click from flashing the row.
            // Measure in .global: the row is moved by `.offset(y:)` during the
            // drag, so a .local space would shift under the gesture and feed
            // the translation back into itself (half-speed, jittery tracking).
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
        .padding(.horizontal, 10)
        // Fixed height so the reorder stride math (rowHeight + gap) is exact,
        // regardless of whether a row shows a notes line.
        .frame(height: 60)
        .background(isDragging || isHovered ? Theme.panelHover : Theme.panel,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isRunningThis ? Theme.accent.opacity(0.65) : Color.white.opacity(isHovered ? 0.12 : 0.04), lineWidth: 1))
        .onHover { isHovered = $0 }
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    /// Two-way binding that writes the new estimate back to the store as soon
    /// as the picker mutates it (the popover's +/- and preset chips both bind
    /// through this).
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

    private func iconButton(_ icon: String, bg: Color, fg: Color = .white,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(fg)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())   // hit area = full 26×26, not just the circle
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(icon == "trash" ? String(localized: "Delete task") : icon == "pause.fill" ? String(localized: "Pause") : isRunningThis ? String(localized: "Resume") : String(localized: "Start focus")))
    }
}

/// Six dots in a 2×3 grid. Used as the drag handle in both the notch and
/// the Tasks window. The grip shape reads as grabbable on its own, so it
/// carries no hover or background chrome.
struct DragHandle: View {
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) { dot; dot }
            HStack(spacing: 3) { dot; dot }
            HStack(spacing: 3) { dot; dot }
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .help("Drag to reorder")
    }

    private var dot: some View {
        Circle()
            .fill(Theme.textSecondary.opacity(0.55))
            .frame(width: 3.5, height: 3.5)
    }
}
