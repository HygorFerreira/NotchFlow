import SwiftUI

/// Simple month grid with prev/next navigation; taps select a day.
/// Layout notes:
/// - Three-letter weekday labels in the user's language, so no two days read
///   the same (two letters collide in Portuguese: Qua/Qui, Seg/Sex).
/// - Today gets an accent outline; the selected day gets a neutral filled tile.
///   Accent dots mark days with unfinished tasks, with a matching legend.
/// - The grid uses indexed IDs (not `Date?.self`) so the leading empty
///   cells don't collide and get deduped by SwiftUI's diff.
struct CalendarView: View {
    @Binding var selectedDate: Date
    /// Start-of-day dates that have at least one unfinished task.
    var busyDays: Set<Date> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleMonth: Date = Date()

    private let cal = Calendar.current
    /// Short weekday names in the user's language, Monday first.
    private let weekdays: [String] = {
        let symbols = Calendar.current.shortWeekdaySymbols   // Sunday first
        return (symbols[1...] + symbols[..<1]).map {
            String($0.replacingOccurrences(of: ".", with: "").prefix(3)).capitalized
        }
    }()
    private let cellHeight: CGFloat = 32
    private let dotSize: CGFloat = 3

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                navButton("chevron.left") { shiftMonth(-1) }
                Spacer()
                Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                navButton("chevron.right") { shiftMonth(1) }
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: cellHeight)
                    }
                }
            }
            HStack(spacing: 12) {
                Label("Today", systemImage: "square")
                Label("Tasks planned", systemImage: "circle.fill")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { visibleMonth = selectedDate }
        .onChange(of: selectedDate) { _, date in
            if !cal.isDate(date, equalTo: visibleMonth, toGranularity: .month) {
                visibleMonth = date
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(day)
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selectedDate = day }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 12, weight: isSelected || isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                // Planned days retain their marker inside the selected tile.
                Circle()
                    .fill(dotColor(isToday: isToday, isBusy: busyDays.contains(cal.startOfDay(for: day)),
                                   isSelected: isSelected))
                    .frame(width: dotSize, height: dotSize)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.selection : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(isToday ? Theme.accent.opacity(0.65) : .clear))
                    .frame(width: 30, height: 30)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FlowCompactButtonStyle())
        .help(busyDays.contains(cal.startOfDay(for: day)) ? String(localized: "Tasks planned") : day.formatted(date: .complete, time: .omitted))
        .accessibilityHint(busyDays.contains(cal.startOfDay(for: day)) ? Text("Tasks planned") : Text(""))
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dotColor(isToday: Bool, isBusy: Bool, isSelected: Bool) -> Color {
        return isBusy ? Theme.accent : .clear
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(FlowCompactButtonStyle())
        .help(icon == "chevron.left" ? String(localized: "Previous month") : String(localized: "Next month"))
        .accessibilityLabel(Text(icon == "chevron.left" ? String(localized: "Previous month") : String(localized: "Next month")))
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = d
        }
    }

    /// Cells for the visible month, padded with nils so the 1st lands on Monday.
    private var monthCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let first = interval.start
        let daysInMonth = cal.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        // Monday-first offset
        let weekday = cal.component(.weekday, from: first)   // 1=Sun…7=Sat
        let leading = (weekday + 5) % 7                       // days before the 1st
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<daysInMonth {
            cells.append(cal.date(byAdding: .day, value: d, to: first))
        }
        return cells
    }
}
