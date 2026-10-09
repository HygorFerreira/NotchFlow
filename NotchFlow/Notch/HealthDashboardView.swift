import SwiftUI

struct HealthDashboardView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            medicationPanel
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 1)

            MedicationActivityHeatmap()
                .frame(width: 204, alignment: .topLeading)
        }
    }

    private var medicationPanel: some View {
        VStack(alignment: .leading, spacing: NotchViewModel.columnSpacing) {
            HStack {
                Label("Medications", systemImage: "pills.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Text(nextMedicationSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.medication)
                    .lineLimit(1)
                    .help("\(store.medicationIntakesToday.count) taken today")
            }
            .frame(height: NotchViewModel.headerHeight)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: NotchViewModel.todoRowGap) {
                    if store.medications.isEmpty {
                        emptyMedicationRow
                    } else {
                        ForEach(store.medications) { medication in
                            medicationRow(medication)
                        }
                    }
                }
            }
            .frame(height: NotchViewModel.todoListHeight)

            Button {
                vm.openMedicationsWindow()
            } label: {
                Label(
                    store.medications.isEmpty ? "Add medication" : "Manage medications",
                    systemImage: store.medications.isEmpty ? "plus" : "slider.horizontal.3"
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: NotchViewModel.addRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func medicationRow(_ medication: Medication) -> some View {
        HStack(spacing: 10) {
            Image(systemName: takenCount(for: medication) > 0 ? "checkmark.circle.fill" : "pills.fill")
                .font(.system(size: 15))
                .foregroundStyle(takenCount(for: medication) > 0 ? Color.green : Theme.medication)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(medication.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(medicationDetail(medication))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                store.recordMedicationTaken(medication)
            } label: {
                Label("Taken", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.green, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!medication.isEnabled)
        }
        .padding(.horizontal, 8)
        .frame(height: NotchViewModel.todoRowHeight)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.panelCorner))
        .opacity(medication.isEnabled ? 1 : 0.55)
    }

    private var emptyMedicationRow: some View {
        Button {
            vm.openMedicationsWindow()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.medication)
                Text("Add your first medication")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: NotchViewModel.todoRowHeight)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.panelCorner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nextMedicationSummary: String {
        guard let reminder = store.nextMedicationReminder() else {
            return String(localized: "No upcoming reminders")
        }

        let time = reminder.date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(reminder.date) {
            return String(localized: "Next: \(reminder.medication.name) · \(time)")
        }
        return String(localized: "Tomorrow: \(reminder.medication.name) · \(time)")
    }

    private func takenCount(for medication: Medication) -> Int {
        store.medicationIntakesToday.filter { $0.medicationID == medication.id }.count
    }

    private func medicationDetail(_ medication: Medication) -> String {
        let times = medication.sortedReminderTimes
            .map { $0.formatted(date: .omitted, time: .shortened) }
            .formatted(.list(type: .and))
        let count = takenCount(for: medication)

        if count > 0 {
            return String(localized: "\(count) taken today · \(times)")
        }
        return medication.dosage.isEmpty ? times : "\(medication.dosage) · \(times)"
    }
}

private struct MedicationActivityHeatmap: View {
    @EnvironmentObject private var store: Store

    private static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private let cell = StreakHeatmap.cell
    private let gap = StreakHeatmap.gap
    private let radius: CGFloat = 5

    var body: some View {
        let counts = countsByDay
        let today = Self.calendar.startOfDay(for: Date())
        let rows = StreakHeatmap.weekRows(for: Date())

        VStack(alignment: .leading, spacing: NotchViewModel.heatmapHeaderSpacing) {
            Label("Medication activity", systemImage: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(height: NotchViewModel.headerHeight)

            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = date(row: row, column: column)
                            let isVisible = day.map { $0 <= today } ?? false
                            RoundedRectangle(cornerRadius: radius)
                                .fill(isVisible ? color(for: counts[day!] ?? 0) : Color.clear)
                                .frame(width: cell, height: cell)
                                .help(day.map(dayHelp) ?? "")
                        }
                    }
                }
            }
        }
    }

    private var countsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for intake in store.medicationIntakes {
            counts[Self.calendar.startOfDay(for: intake.takenAt), default: 0] += 1
        }
        return counts
    }

    private func date(row: Int, column: Int) -> Date? {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: Date())
        guard let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) else { return nil }

        let leading = (calendar.component(.weekday, from: firstOfMonth) + 5) % 7
        let dayIndex = row * 7 + column - leading
        guard dayIndex >= 0,
              let candidate = calendar.date(byAdding: .day, value: dayIndex, to: firstOfMonth),
              calendar.isDate(candidate, equalTo: today, toGranularity: .month) else {
            return nil
        }
        return candidate
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Theme.streakEmpty
        case 1: return Theme.medication.opacity(0.42)
        case 2: return Theme.medication.opacity(0.68)
        default: return Theme.medication
        }
    }

    private func dayHelp(_ day: Date) -> String {
        let count = countsByDay[Self.calendar.startOfDay(for: day), default: 0]
        return String(localized: "\(day.formatted(date: .abbreviated, time: .omitted)): \(count) doses taken")
    }
}
