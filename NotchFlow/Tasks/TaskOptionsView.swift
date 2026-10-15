import SwiftUI

struct TaskOptionsView: View {
    @EnvironmentObject private var store: Store
    @Binding var project: String
    @Binding var tagsText: String
    @Binding var recurrence: TaskRecurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Project (optional)", text: $project)
                    .onChange(of: project) { _, value in project = String(value.prefix(80)) }
                if !store.projects.isEmpty {
                    Menu {
                        Button("No project") { project = "" }
                        ForEach(store.projects, id: \.self) { name in
                            Button(name) { project = name }
                        }
                    } label: { Image(systemName: "folder") }
                    .accessibilityLabel("Choose project")
                }
            }
            TextField("Tags separated by commas", text: $tagsText)
                .onChange(of: tagsText) { _, value in tagsText = String(value.prefix(200)) }
            Picker("Repeat", selection: $recurrence.frequency) {
                ForEach(TaskRecurrence.Frequency.allCases, id: \.self) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            .onChange(of: recurrence.frequency) { _, frequency in
                if frequency == .custom && recurrence.weekdays.isEmpty {
                    recurrence.weekdays = [Calendar.current.component(.weekday, from: Date())]
                }
            }
            if recurrence.frequency == .custom {
                HStack(spacing: 4) {
                    ForEach(0..<7) { offset in
                        let day = (Calendar.current.firstWeekday - 1 + offset) % 7 + 1
                        Button {
                            if recurrence.weekdays.contains(day) { recurrence.weekdays.remove(day) }
                            else { recurrence.weekdays.insert(day) }
                        } label: {
                            Text(Calendar.current.shortStandaloneWeekdaySymbols[day - 1])
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .foregroundStyle(recurrence.weekdays.contains(day) ? Theme.textPrimary : Theme.textSecondary)
                                .background(recurrence.weekdays.contains(day) ? Theme.selection : Theme.control,
                                            in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(recurrence.weekdays.contains(day) ? .isSelected : [])
                    }
                }
            }
            if recurrence.frequency != .none {
                Text("Completing this task creates the next occurrence. Missed days are skipped.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .textFieldStyle(FlowTextFieldStyle())
    }
}

struct TaskFiltersView: View {
    @EnvironmentObject private var store: Store
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All projects") { store.selectedProject = nil }
                ForEach(store.projects, id: \.self) { project in
                    Button(project) { store.selectedProject = project }
                }
            } label: {
                Label(store.selectedProject ?? (compact ? String(localized: "Projects") : String(localized: "All projects")), systemImage: "folder")
                    .lineLimit(1)
            }
            Menu {
                Button("All tags") { store.selectedTag = nil }
                ForEach(store.allTags, id: \.self) { tag in
                    Button("#\(tag)") { store.selectedTag = tag }
                }
            } label: {
                Label(store.selectedTag.map { "#\($0)" } ?? (compact ? String(localized: "Tags") : String(localized: "All tags")), systemImage: "tag")
                    .lineLimit(1)
            }
            if store.selectedProject != nil || store.selectedTag != nil {
                Button {
                    store.selectedProject = nil
                    store.selectedTag = nil
                } label: { Image(systemName: "xmark.circle.fill") }
                .accessibilityLabel("Clear filters")
            }
        }
        .font(.system(size: 11))
    }
}
