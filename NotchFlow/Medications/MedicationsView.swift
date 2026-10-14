import SwiftUI

struct MedicationsView: View {
    @Environment(\.workspaceNavigation) private var workspace
    @EnvironmentObject private var store: Store
    @State private var editingMedication: Medication?
    @State private var showingAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 12) {
                Label("Active reminders: \(store.medications.filter(\.isEnabled).count)", systemImage: "bell.badge")
                Spacer()
                Label("Taken today: \(store.medicationIntakesToday.count)", systemImage: "checkmark.circle")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            if store.medications.isEmpty {
                emptyState
            } else {
                medicationList
            }
        }
        .frame(minWidth: workspace == nil ? 640 : 0, minHeight: workspace == nil ? 460 : 0)
        .background(Theme.windowBackground)
        .safeAreaInset(edge: .top, spacing: 0) { FlowWindowNavigation(current: .medications) }
        .flowAppearance()
        .sheet(isPresented: $showingAddForm) {
            MedicationFormView { name, dosage, times in
                store.addMedication(name: name, dosage: dosage, reminderTimes: times)
            }
        }
        .sheet(item: $editingMedication) { medication in
            MedicationFormView(medication: medication) { name, dosage, times in
                var updated = medication
                updated.name = name
                updated.dosage = dosage
                updated.reminderTimes = times
                store.updateMedication(updated)
            }
        }
    }

    private var header: some View {
        HStack {
            FlowPageHeading(title: "Medications", subtitle: "Daily reminders for your medication",
                            symbol: "pills.fill", color: Theme.medication)

            Spacer()

            Button {
                showingAddForm = true
            } label: {
                Label("Add medication", systemImage: "plus")
            }
            .buttonStyle(FlowButtonStyle(prominent: true))
            .keyboardShortcut("n")
        }
        .padding(24)
    }

    private var medicationList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.medications) { medication in
                    MedicationRow(
                        medication: medication,
                        lastIntake: store.medicationIntakesToday.first { $0.medicationID == medication.id },
                        onUndo: {
                            if let intake = store.medicationIntakesToday.first(where: { $0.medicationID == medication.id }) {
                                store.deleteMedicationIntake(intake)
                            }
                        },
                        onToggle: { store.setMedicationEnabled(medication, enabled: $0) },
                        onTaken: { store.recordMedicationTaken(medication) },
                        onEdit: { editingMedication = medication },
                        onDelete: { store.deleteMedication(medication) }
                    )
                }

                if !store.medicationIntakesToday.isEmpty {
                    Text("Taken today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    ForEach(store.medicationIntakesToday) { intake in
                        intakeRow(intake)
                    }
                }
            }
            .padding(24)
        }
    }

    private func intakeRow(_ intake: MedicationIntake) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)

            VStack(alignment: .leading, spacing: 2) {
                Text(intake.medicationName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(intake.dosage.isEmpty
                     ? intake.takenAt.formatted(date: .omitted, time: .shortened)
                     : "\(intake.dosage) · \(intake.takenAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                store.deleteMedicationIntake(intake)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove this record")
            .accessibilityLabel("Remove medication intake record")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text("No medications yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add a medication and choose one or more daily reminder times.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
            Button("Add medication") {
                showingAddForm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct MedicationRow: View {
    let medication: Medication
    let lastIntake: MedicationIntake?
    let onUndo: () -> Void
    let onToggle: (Bool) -> Void
    let onTaken: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.system(size: 18))
                .foregroundStyle(medication.isEnabled ? Theme.medication : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(medication.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if !medication.dosage.isEmpty {
                        Text(medication.dosage)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text(timeDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                if let lastIntake {
                    HStack(spacing: 8) {
                        Text("Last recorded at \(lastIntake.takenAt.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(Theme.success)
                        Button("Undo", action: onUndo)
                            .buttonStyle(.borderless)
                    }
                    .font(.system(size: 11))
                }
            }

            Spacer()

            Button(action: onTaken) {
                Label("Taken", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.success)
            .disabled(!medication.isEnabled)

            Toggle("", isOn: Binding(
                get: { medication.isEnabled },
                set: onToggle
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(Text("Enable medication reminder"))

            Menu {
                Button("Edit", action: onEdit)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
            .accessibilityLabel("Medication actions")
        }
        .padding(12)
        .flowSurface()
        .opacity(medication.isEnabled ? 1 : 0.65)
    }

    private var timeDescription: String {
        medication.sortedReminderTimes
            .map { $0.formatted(date: .omitted, time: .shortened) }
            .formatted(.list(type: .and))
    }
}

struct MedicationFormView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalReminderTimes: [Date]
    @State private var confirmDiscard = false
    private let medication: Medication?
    private let onSave: (String, String, [Date]) -> Void

    @State private var name: String
    @State private var dosage: String
    @State private var reminderTimes: [Date]
    @FocusState private var nameFocused: Bool

    init(
        medication: Medication? = nil,
        onSave: @escaping (String, String, [Date]) -> Void
    ) {
        self.medication = medication
        self.onSave = onSave
        _name = State(initialValue: medication?.name ?? "")
        _dosage = State(initialValue: medication?.dosage ?? "")
        let times = medication?.reminderTimes ?? [Self.defaultTime]
        originalReminderTimes = times
        _reminderTimes = State(initialValue: times)
    }

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            FlowPageHeading(title: medication == nil ? "Add medication" : "Edit medication",
                            subtitle: "Choose your daily reminder times", symbol: "pills.fill", color: Theme.medication)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Medication name", text: $name)
                    .textFieldStyle(FlowTextFieldStyle())
                    .focused($nameFocused)
                    .onChange(of: name) { _, newValue in
                        name = String(newValue.prefix(Medication.nameLimit))
                    }

                TextField("Dose (optional, e.g. 10 mg)", text: $dosage)
                    .textFieldStyle(FlowTextFieldStyle())
                    .onChange(of: dosage) { _, newValue in
                        dosage = String(newValue.prefix(Medication.dosageLimit))
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Reminder times")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button {
                        reminderTimes.append(Self.defaultTime)
                    } label: {
                        Label("Add time", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }

                ForEach(reminderTimes.indices, id: \.self) { index in
                    HStack {
                        DatePicker(
                            "Time",
                            selection: $reminderTimes[index],
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()

                        Spacer()

                        Button {
                            reminderTimes.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(reminderTimes.count == 1)
                        .accessibilityLabel("Remove reminder time")
                    }
                }
            }


        }
        .padding(24)
        }
        Divider()
        actionBar.padding(20)
        }
        .frame(width: 500, height: 520)
        .background(Theme.windowBackground)
        .flowAppearance()
        .onAppear { nameFocused = true }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("Save changes before closing?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Save", action: saveAndClose).disabled(!canSave)
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your unsaved changes will be lost if you discard them.")
        }
    }

    private var actionBar: some View {
            HStack {
                Spacer()
                Button("Cancel") {
                    if hasChanges { confirmDiscard = true } else { dismiss() }
                }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(FlowButtonStyle())
                Button("Save", action: saveAndClose)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(FlowButtonStyle(prominent: true))
                .disabled(!canSave)
            }
    }

    private var hasChanges: Bool {
        name != (medication?.name ?? "") || dosage != (medication?.dosage ?? "")
            || reminderTimes != originalReminderTimes
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func saveAndClose() {
        guard canSave else { return }
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines),
               dosage.trimmingCharacters(in: .whitespacesAndNewlines), reminderTimes)
        dismiss()
    }

    private static var defaultTime: Date {
        Calendar.current.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }
}
