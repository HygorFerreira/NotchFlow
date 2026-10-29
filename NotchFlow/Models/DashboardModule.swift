import Foundation

enum DashboardModule: String, CaseIterable, Identifiable {
    case activity = "Activity", health = "Health", machine = "Machine", water = "Water", ai = "AI", music = "Music", tools = "Tools"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .activity: return "checklist"
        case .health: return "heart.fill"
        case .machine: return "desktopcomputer"
        case .water: return "drop.fill"
        case .ai: return "sparkles"
        case .music: return "music.note"
        case .tools: return "square.grid.2x2"
        }
    }

    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        let valid = values.filter { DashboardModule(rawValue: $0) != nil && seen.insert($0).inserted }
        return valid.isEmpty ? [DashboardModule.activity.rawValue] : valid
    }
}

enum RoutineBreak: String, CaseIterable {
    case eyes, posture
    var title: String { self == .eyes ? "Rest your eyes" : "Time to stretch" }
    var detail: String { self == .eyes ? "Look into the distance for 20 seconds" : "Stand up and change your posture" }
    var symbol: String { self == .eyes ? "eye" : "figure.stand" }
}

/// Deadlines use wall time so sleep/wake never produces a burst of catch-up alerts.
struct BreakSchedule {
    private(set) var deadline: Date?
    private var interval: Int?

    mutating func update(enabled: Bool, minutes: Int, now: Date) {
        let value = min(180, max(15, minutes))
        guard enabled else { deadline = nil; interval = nil; return }
        if interval != value || deadline == nil {
            interval = value
            deadline = now.addingTimeInterval(Double(value) * 60)
        }
    }

    func isDue(at now: Date) -> Bool { deadline.map { $0 <= now } ?? false }
    mutating func deferUntil(_ now: Date, minutes: Int? = nil) {
        guard let interval else { return }
        deadline = now.addingTimeInterval(Double(minutes ?? interval) * 60)
    }
}
