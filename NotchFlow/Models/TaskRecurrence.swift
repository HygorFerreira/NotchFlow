import Foundation

struct TaskRecurrence: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable {
        case none, daily, weekly, custom

        var title: String {
            switch self {
            case .none: return String(localized: "Does not repeat")
            case .daily: return String(localized: "Every day")
            case .weekly: return String(localized: "Every week")
            case .custom: return String(localized: "Selected weekdays")
            }
        }
    }

    var frequency: Frequency = .none
    /// Calendar weekday numbers: Sunday = 1, Saturday = 7.
    var weekdays: Set<Int> = []

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: date)
        switch frequency {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: day)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: day)
        case .custom:
            for offset in 1...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
                if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
            }
            return nil
        }
    }

    var isValid: Bool { frequency != .custom || !weekdays.intersection(1...7).isEmpty }
}
