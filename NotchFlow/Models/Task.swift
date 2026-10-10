import Foundation

/// A single to-do / focus task.
struct Task: Identifiable, Codable, Hashable {
    /// Max characters accepted in the title / notes fields.
    static let titleLimit = 150
    static let notesLimit = 500

    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    /// The calendar day this task is scheduled for. `nil` == unscheduled.
    var scheduledDate: Date?
    /// Planned focus duration in minutes (the focus estimate, e.g. 25).
    var estimateMinutes: Int = 25
    var isDone: Bool = false
    var createdAt: Date = Date()
    /// Total focused seconds accumulated against this task.
    var focusedSeconds: Int = 0
    /// User-controlled display order. Tasks sort by this ascending; ties break
    /// on `createdAt`. Legacy tasks (decoded from a pre-reorder data file) come
    /// back with `0` and `Store.load()` migrates them to a stable range.
    var sortOrder: Double = 0
    var project: String = ""
    var tags: [String] = []
    var recurrence: TaskRecurrence = TaskRecurrence()
    /// Links a generated occurrence to its predecessor to avoid duplicates.
    var recurrenceParentID: UUID?
    var completedAt: Date?
    /// Only the hour/minute are used, combined with scheduledDate locally.
    var startTime: Date?
    var reminderMinutesBefore: Int?

    var scheduledStart: Date? {
        guard let scheduledDate, let startTime else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        return Calendar.current.date(bySettingHour: components.hour ?? 0,
                                     minute: components.minute ?? 0, second: 0, of: scheduledDate)
    }

    func reminderDate(after now: Date = Date()) -> Date? {
        guard !isDone, let start = scheduledStart, let minutes = reminderMinutesBefore else { return nil }
        let date = start.addingTimeInterval(-Double(max(0, minutes)) * 60)
        return date > now ? date : nil
    }

    var estimateLabel: String {
        estimateMinutes >= 60
            ? "\(estimateMinutes / 60)h\(estimateMinutes % 60 == 0 ? "" : "\(estimateMinutes % 60)m")"
            : "\(estimateMinutes)m"
    }

    init(title: String,
         notes: String = "",
         scheduledDate: Date? = Date(),
         estimateMinutes: Int = 25,
         isDone: Bool = false,
         createdAt: Date = Date(),
         focusedSeconds: Int = 0,
         sortOrder: Double = 0,
         project: String = "",
         tags: [String] = [],
         recurrence: TaskRecurrence = TaskRecurrence(),
         startTime: Date? = nil,
         reminderMinutesBefore: Int? = nil) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.scheduledDate = scheduledDate
        self.estimateMinutes = estimateMinutes
        self.isDone = isDone
        self.createdAt = createdAt
        self.focusedSeconds = focusedSeconds
        self.sortOrder = sortOrder
        self.project = project
        self.tags = tags
        self.recurrence = recurrence
        self.completedAt = isDone ? Date() : nil
        self.startTime = startTime
        self.reminderMinutesBefore = reminderMinutesBefore
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, scheduledDate, estimateMinutes, isDone
        case createdAt, focusedSeconds, sortOrder
        case project, tags, recurrence, recurrenceParentID, completedAt
        case startTime, reminderMinutesBefore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decode(String.self, forKey: .notes)
        scheduledDate = try c.decodeIfPresent(Date.self, forKey: .scheduledDate)
        estimateMinutes = min(FocusSettings.focusRange.upperBound, max(FocusSettings.focusRange.lowerBound,
            try c.decode(Int.self, forKey: .estimateMinutes)))
        isDone = try c.decode(Bool.self, forKey: .isDone)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        focusedSeconds = try c.decode(Int.self, forKey: .focusedSeconds)
        // Missing field == pre-reorder data; default 0 lets `Store.load()`
        // assign stable values once.
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        recurrence = try c.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? TaskRecurrence()
        recurrenceParentID = try c.decodeIfPresent(UUID.self, forKey: .recurrenceParentID)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        startTime = try c.decodeIfPresent(Date.self, forKey: .startTime)
        reminderMinutesBefore = try c.decodeIfPresent(Int.self, forKey: .reminderMinutesBefore)
    }

    static func normalizedTags(_ text: String) -> [String] {
        Array(Set(text.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        }.filter { !$0.isEmpty })).sorted()
    }

    var organizationLabel: String {
        ([project].filter { !$0.isEmpty } + tags.map { "#\($0)" }).joined(separator: " · ")
    }
}
