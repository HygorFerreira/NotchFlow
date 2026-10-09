import Foundation

struct WeeklySummary {
    struct Day: Identifiable {
        var id: Date { date }
        let date: Date
        let seconds: TimeInterval
    }

    struct TaskTime: Identifiable {
        let id: UUID?
        let title: String
        let project: String
        let seconds: TimeInterval
    }

    let interval: DateInterval
    let days: [Day]
    let taskTimes: [TaskTime]
    let completedTasks: Int
    let completedBlocks: Int
    let previousWeekSeconds: TimeInterval
    var totalSeconds: TimeInterval { days.reduce(0) { $0 + $1.seconds } }

    init(date: Date, tasks: [Task], sessions: [FocusSession], calendar: Calendar = .current) {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        interval = DateInterval(start: start, end: end)
        days = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return Day(date: day, seconds: Self.focusSeconds(sessions, start: day, end: next))
        }
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        previousWeekSeconds = Self.focusSeconds(sessions, start: previousStart, end: start)
        completedTasks = tasks.filter {
            guard $0.isDone, let completedAt = $0.completedAt else { return false }
            return completedAt >= start && completedAt < end
        }.count
        completedBlocks = sessions.filter { $0.completed && $0.endedAt >= start && $0.endedAt < end }.count

        var byTask: [UUID?: TimeInterval] = [:]
        for session in sessions {
            let seconds = Self.overlap(session, start: start, end: end)
            if seconds > 0 { byTask[session.taskId, default: 0] += seconds }
        }
        let tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        taskTimes = byTask.map { id, seconds in
            let task = id.flatMap { tasksByID[$0] }
            return TaskTime(id: id,
                            title: task?.title ?? (id == nil ? String(localized: "Unassigned focus") : String(localized: "Deleted task")),
                            project: task?.project ?? "", seconds: seconds)
        }.sorted {
            if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
            return $0.title < $1.title
        }
    }

    private static func overlap(_ session: FocusSession, start: Date, end: Date) -> TimeInterval {
        max(0, min(session.endedAt, end).timeIntervalSince(max(session.startedAt, start)))
    }

    private static func focusSeconds(_ sessions: [FocusSession], start: Date, end: Date) -> TimeInterval {
        sessions.reduce(0) { $0 + overlap($1, start: start, end: end) }
    }
}
