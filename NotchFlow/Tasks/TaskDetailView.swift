import SwiftUI

/// Modal sheet to view/edit a single task: title, notes, focus time, date,
/// completion — plus start / delete actions.
struct TaskDetailView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var focus: FocusTimer
    @Environment(\.dismiss) private var dismiss

    @Environment(\.undoManager) private var undoManager
    @State private var confirmDiscard = false
    private let original: Task
    @State private var draft: Task
    @State private var tagsText: String

    init(task: Task) {
        original = task
        _draft = State(initialValue: task)
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
    }

    private var hasChanges: Bool {
        var edited = draft
        edited.tags = Task.normalizedTags(tagsText)
        return edited != original
    }

    private func requestClose() {
        if hasChanges { confirmDiscard = true } else { dismiss() }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.recurrence.isValid
            && Task.isValidTimeRange(start: draft.startTime, end: draft.endTime)
    }

    private func saveDraft() {
        draft.tags = Task.normalizedTags(tagsText)
        store.update(draft)
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Task")
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { requestClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }

            field("Title", count: draft.title.count, limit: Task.titleLimit) {
                TextField("Task title", text: $draft.title)
                    .textFieldStyle(FlowTextFieldStyle())
                    .onChange(of: draft.title) { _, new in
                        if new.count > Task.titleLimit {
                            draft.title = String(new.prefix(Task.titleLimit))
                        }
                    }
            }

            field("Notes", count: draft.notes.count, limit: Task.notesLimit) {
                TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(FlowTextFieldStyle())
                    .lineLimit(2...5)
                    .onChange(of: draft.notes) { _, new in
                        if new.count > Task.notesLimit {
                            draft.notes = String(new.prefix(Task.notesLimit))
                        }
                    }
            }

            HStack(alignment: .top, spacing: 12) {
                // Focus-time editor: refined popover picker (clock icon +
                // current value, tap to open a macOS-Clock-style popover
                // with +/- and preset chips).
                field("Focus time") {
                    FocusTimePicker(
                        minutes: $draft.estimateMinutes,
                        range: FocusSettings.focusRange,
                        presets: [15, 25, 30, 45, 60, 90]
                    )
                }
                field("Date") {
                    DatePicker("", selection: Binding(
                        get: { draft.scheduledDate ?? Date() },
                        set: { draft.scheduledDate = $0 }),
                        displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                }
            }

            TaskScheduleView(date: $draft.scheduledDate, startTime: $draft.startTime, endTime: $draft.endTime,
                             reminderMinutesBefore: $draft.reminderMinutesBefore)
            TaskOptionsView(project: $draft.project, tagsText: $tagsText, recurrence: $draft.recurrence)

            Toggle(isOn: $draft.isDone) {
                Text("Completed").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)
            .padding(.top, 2)


        }
        .padding(24)
        }
        Divider()
        actionBar.padding(20)
        }
        .frame(width: 480)
        .frame(maxHeight: 700)
        .background(Theme.windowBackground)
        .flowAppearance()
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("Save changes before closing?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Save") { saveDraft(); dismiss() }.disabled(!canSave)
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your unsaved changes will be lost if you discard them.")
        }
    }

    private var actionBar: some View {
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    store.delete(draft, undoManager: undoManager); dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 13))
                        
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    saveDraft(); focus.start(task: draft); dismiss()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowButtonStyle())
                .disabled(!canSave || draft.isDone)
                Button {
                    saveDraft(); dismiss()
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
    }

    private func field<Content: View>(_ label: String,
                                      count: Int? = nil,
                                      limit: Int? = nil,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.localized.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let count, let limit {
                    Text("\(count)/\(limit)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(count >= limit ? Theme.accent : Theme.textSecondary)
                }
            }
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
