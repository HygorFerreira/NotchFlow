import SwiftUI

/// Seven days of focus, with three 40-minute cells in each two-hour band.
/// The dense grid in the reference represents actual recorded focus intervals.
struct FocusActivityHeatmap: View {
    @EnvironmentObject private var store: Store
    private let calendar = Calendar.current
    private let slotSeconds: TimeInterval = 40 * 60

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: today) }
        let values = days.map(fractions)
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchPalette.text)
            HStack(spacing: 5) {
                Color.clear.frame(width: 22)
                ForEach(days, id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 8))
                        .foregroundStyle(NotchPalette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 12)
            HStack(spacing: 5) {
                VStack(spacing: 0) {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(String(format: "%02dh", hour))
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(NotchPalette.secondary)
                        if hour != 24 { Spacer(minLength: 0) }
                    }
                }
                .frame(width: 22)
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 2) {
                        ForEach(0..<12, id: \.self) { row in
                            HStack(spacing: 1.5) {
                                ForEach(0..<3, id: \.self) { column in
                                    let fraction = values[index][row * 3 + column]
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(fraction > 0 ? NotchPalette.accent.opacity(0.35 + 0.65 * fraction) : Color(hex: "#353941"))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(String(localized: "\(Int(values[index].reduce(0, +) * 40)) min"))
                }
            }
        }
        .padding(12)
        .background(NotchPalette.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NotchPalette.border))
    }

    private func fractions(for day: Date) -> [Double] {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return Array(repeating: 0, count: 36) }
        let sessions = store.sessions.filter { $0.startedAt < nextDay && $0.endedAt > day }
        return (0..<36).map { index in
            // Calendar arithmetic preserves the labels across daylight-saving changes.
            let minutes = index * 40
            let start = calendar.date(bySettingHour: minutes / 60,
                                      minute: minutes % 60, second: 0, of: day) ?? day
            let end = min(nextDay, start.addingTimeInterval(slotSeconds))
            let seconds = sessions.reduce(0.0) { total, session in
                total + max(0, min(session.endedAt, end).timeIntervalSince(max(session.startedAt, start)))
            }
            return min(1, seconds / slotSeconds)
        }
    }
}
