import Foundation
import SwiftUI

/// Single source of truth for tasks + focus sessions, persisted to JSON in
/// Application Support. All mutations happen on the main actor.
@MainActor
final class Store: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var sessions: [FocusSession] = []
    @Published private(set) var waterIntakes: [WaterIntake] = []
    @Published private(set) var hydrationSettings = HydrationSettings()
    @Published var medications: [Medication] = []
    @Published var medicationIntakes: [MedicationIntake] = []
    @Published private(set) var persistenceError: String?
    @Published private(set) var recoveryNotice: String?
    private var lastSavedData: Data?
    private var needsRecoveryCopy = false
    private var loadFailed = false
    var canRetrySave: Bool { !loadFailed }
    var backupFileURL: URL { fileURL.appendingPathExtension("backup") }
    /// Saved as soon as it changes. Settings used to persist only when a task
    /// changed afterwards, so a tweak followed by Quit was lost.
    @Published var settings: FocusSettings = .default {
        didSet { if settings != oldValue && !isLoading { save() } }
    }

    /// Set while `load()` fills the properties, so reading the file doesn't
    /// write it straight back.
    private var isLoading = false

    /// Routing bus: set to a task id to request the Tasks window open its detail.
    @Published var pendingOpenTaskID: UUID?
    @Published var selectedProject: String?
    @Published var selectedTag: String?

    /// Called when a task is completed or deleted so dependents (the focus timer)
    /// can stop any running session for it. Wired up by the app. `record` says
    /// whether the in-flight session should still be persisted (true on complete,
    /// false on delete — a deleted task has nowhere to count time against).
    var onTaskDeactivated: (_ id: UUID, _ record: Bool) -> Void = { _, _ in }

    /// Called after a task is edited, so a running block can pick up a new
    /// length or title. Wired up by the app.
    var onTaskUpdated: (_ task: Task) -> Void = { _ in }

    private let fileURL: URL
    private let taskReminderScheduler: @MainActor ([Task]) -> Void
    /// The JSON file everything is saved in, for "Show in Finder".
    var dataFileURL: URL { fileURL }

    /// `fileURL` defaults to Application Support/NotchFlow/data.json; the
    /// Debug snapshot mode points it at a scratch file instead.
    init(fileURL: URL? = nil,
         taskReminderScheduler: @escaping @MainActor ([Task]) -> Void = {
             NotificationService.shared.scheduleTaskReminders(for: $0)
         }) {
        self.taskReminderScheduler = taskReminderScheduler
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NotchFlow", isDirectory: true)
            self.fileURL = base.appendingPathComponent("data.json")
        }
        load()
    }

    // MARK: - Task operations

    /// Add a new task. `estimate` defaults to the user's current `focusMinutes`
    /// setting; pass an explicit value to override per task.
    func add(title: String, notes: String = "", estimate: Int? = nil, date: Date? = Date(),
             project: String = "", tags: [String] = [], recurrence: TaskRecurrence = TaskRecurrence(),
             startTime: Date? = nil, reminderMinutesBefore: Int? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, recurrence.isValid else { return }
        let est = estimate ?? settings.focusMinutes
        let nextOrder = (tasks.map(\.sortOrder).max() ?? 0) + 1024
        tasks.append(Task(title: String(title.prefix(Task.titleLimit)), notes: String(notes.prefix(Task.notesLimit)),
                          scheduledDate: recurrence.frequency == .none ? date : (date ?? Date()),
                          estimateMinutes: min(180, max(1, est)), sortOrder: nextOrder,
                          project: project.trimmingCharacters(in: .whitespacesAndNewlines),
                          tags: Task.normalizedTags(tags.joined(separator: ",")), recurrence: recurrence,
                          startTime: startTime, reminderMinutesBefore: reminderMinutesBefore))
        save()
        rescheduleTaskReminders()
    }

    func update(_ task: Task) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.recurrence.isValid else { return }
        let wasDone = tasks[idx].isDone
        var updated = task
        updated.title = String(task.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Task.titleLimit))
        updated.notes = String(task.notes.prefix(Task.notesLimit))
        updated.estimateMinutes = min(FocusSettings.focusRange.upperBound, max(FocusSettings.focusRange.lowerBound, task.estimateMinutes))
        // Editors hold a snapshot. Activity recorded and ordering changed while
        // that editor was open belong to the live store, not the draft.
        updated.focusedSeconds = tasks[idx].focusedSeconds
        updated.sortOrder = tasks[idx].sortOrder
        updated.createdAt = tasks[idx].createdAt
        updated.recurrenceParentID = tasks[idx].recurrenceParentID
        updated.project = task.project.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tags = Task.normalizedTags(task.tags.joined(separator: ","))
        if updated.recurrence.frequency != .none && updated.scheduledDate == nil {
            updated.scheduledDate = Date()
        }
        updated.completedAt = updated.isDone ? (wasDone ? tasks[idx].completedAt : Date()) : nil
        tasks[idx] = updated
        if updated.isDone && !wasDone {
            onTaskDeactivated(updated.id, true)
            createNextOccurrence(for: updated)
        }
        save()
        onTaskUpdated(updated)
        rescheduleTaskReminders()
    }

    func delete(_ task: Task, undoManager: UndoManager? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        // Capture the live value, since an editor can hold an older draft.
        let deleted = tasks[index]
        onTaskDeactivated(task.id, false)
        tasks.remove(at: index)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.restoreDeletedTask(deleted, at: index, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Delete task"))
        save()
        rescheduleTaskReminders()
    }

    private func restoreDeletedTask(_ task: Task, at index: Int, undoManager: UndoManager?) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.insert(task, at: min(index, tasks.count))
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] store in
            store.delete(task, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Delete task"))
        // Restore data and reminders; a deleted timer must never restart itself.
        save()
        rescheduleTaskReminders()
    }

    func toggleDone(_ task: Task) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isDone.toggle()
        tasks[idx].completedAt = tasks[idx].isDone ? Date() : nil
        // Completing a task stops its running session (resets the progress line)
        // and keeps the focus time it earned.
        if tasks[idx].isDone {
            onTaskDeactivated(task.id, true)
            createNextOccurrence(for: tasks[idx])
        }
        save()
        rescheduleTaskReminders()
    }

    private func createNextOccurrence(for task: Task) {
        guard !tasks.contains(where: { $0.recurrenceParentID == task.id }),
              let scheduled = task.scheduledDate,
              let nextDate = task.recurrence.nextDate(after: scheduled) else { return }
        // Skip missed occurrences without creating a backlog. Preserve the weekly
        // anchor by advancing the rule from each scheduled occurrence.
        var date = nextDate
        let today = Calendar.current.startOfDay(for: Date())
        while date < today {
            guard let next = task.recurrence.nextDate(after: date), next > date else { return }
            date = next
        }
        var next = Task(title: task.title, notes: task.notes, scheduledDate: date,
                        estimateMinutes: task.estimateMinutes,
                        sortOrder: (tasks.map(\.sortOrder).max() ?? 0) + 1024,
                        project: task.project, tags: task.tags, recurrence: task.recurrence,
                        startTime: task.startTime, reminderMinutesBefore: task.reminderMinutesBefore)
        next.recurrenceParentID = task.id
        tasks.append(next)
    }

    func rescheduleTaskReminders() {
        taskReminderScheduler(tasks)
    }

    var projects: [String] { Array(Set(tasks.map(\.project).filter { !$0.isEmpty })).sorted() }
    var allTags: [String] { Array(Set(tasks.flatMap(\.tags))).sorted() }

    func filteredTasks(_ list: [Task]) -> [Task] {
        list.filter { task in
            (selectedProject == nil || task.project == selectedProject)
                && (selectedTag.map { task.tags.contains($0) } ?? true)
        }
    }

    /// Reorder tasks within a visible list (e.g. today's tasks or the
    /// unscheduled bucket). The caller passes the list the user is looking at
    /// so the source/destination indices line up with what they see; we
    /// re-stamp the moved tasks' `sortOrder` in their new positions using
    /// 1024-step spacing. Collisions across lists don't matter because each
    /// list is sorted independently.
    func moveTasks(in list: [Task], from source: IndexSet, to destination: Int) {
        // A live filter/deletion can change the list while a drag is in flight.
        guard !source.isEmpty, source.allSatisfy({ list.indices.contains($0) }),
              (0...list.count).contains(destination) else { return }
        var working = list
        working.move(fromOffsets: source, toOffset: destination)
        for (i, t) in working.enumerated() {
            if let idx = tasks.firstIndex(where: { $0.id == t.id }) {
                tasks[idx].sortOrder = Double(i + 1) * 1024
            }
        }
        save()
    }

    /// Accessible alternative to dragging, resolved by identity rather than a stale row index.
    func moveTask(_ task: Task, in list: [Task], by offset: Int) {
        guard offset == -1 || offset == 1,
              tasks.contains(where: { $0.id == task.id }),
              let source = list.firstIndex(where: { $0.id == task.id }) else { return }
        let target = source + offset
        guard list.indices.contains(target), list[target].isDone == task.isDone else { return }
        moveTasks(in: list, from: IndexSet(integer: source), to: target > source ? target + 1 : target)
    }

    // MARK: - Hydration

    func updateHydrationSettings(_ settings: HydrationSettings) {
        var settings = settings
        settings.glassMilliliters = min(3000, max(50, settings.glassMilliliters))
        settings.bottleMilliliters = min(3000, max(50, settings.bottleMilliliters))
        settings.goalMilliliters = min(10000, max(250, settings.goalMilliliters))
        settings.reminderIntervalMinutes = min(180, max(15, settings.reminderIntervalMinutes))
        hydrationSettings = settings
        save()
    }

    func recordWater(at date: Date = Date()) {
        waterIntakes.append(WaterIntake(milliliters: hydrationSettings.servingMilliliters,
                                       container: hydrationSettings.container, recordedAt: date))
        save()
    }

    func deleteWaterIntake(_ intake: WaterIntake) {
        waterIntakes.removeAll { $0.id == intake.id }
        save()
    }

    func waterIntakes(on date: Date, calendar: Calendar = .current) -> [WaterIntake] {
        waterIntakes.filter { calendar.isDate($0.recordedAt, inSameDayAs: date) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func waterTotal(on date: Date, calendar: Calendar = .current) -> Int {
        waterIntakes(on: date, calendar: calendar).reduce(0) { $0 + $1.milliliters }
    }

    // MARK: - Medication operations

    func addMedication(name: String, dosage: String, reminderTimes: [Date]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !reminderTimes.isEmpty else { return }

        let medication = Medication(
            name: trimmedName,
            dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
            reminderTimes: reminderTimes
        )
        medications.append(medication)
        save()
        NotificationService.shared.scheduleReminders(for: medication)
    }

    func updateMedication(_ medication: Medication) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        medications[index] = medication
        save()
        NotificationService.shared.scheduleReminders(for: medication)
    }

    func setMedicationEnabled(_ medication: Medication, enabled: Bool) {
        guard let index = medications.firstIndex(where: { $0.id == medication.id }) else { return }
        medications[index].isEnabled = enabled
        save()

        if enabled {
            NotificationService.shared.scheduleReminders(for: medications[index])
        } else {
            NotificationService.shared.cancelReminders(for: medication.id)
        }
    }

    func deleteMedication(_ medication: Medication) {
        medications.removeAll { $0.id == medication.id }
        save()
        NotificationService.shared.cancelReminders(for: medication.id)
    }

    func recordMedicationTaken(_ medication: Medication, at date: Date = Date()) {
        medicationIntakes.append(
            MedicationIntake(
                medicationID: medication.id,
                medicationName: medication.name,
                dosage: medication.dosage,
                takenAt: date
            )
        )
        save()
    }

    func deleteMedicationIntake(_ intake: MedicationIntake) {
        medicationIntakes.removeAll { $0.id == intake.id }
        save()
    }

    var medicationIntakesToday: [MedicationIntake] {
        medicationIntakes
            .filter { Calendar.current.isDateInToday($0.takenAt) }
            .sorted { $0.takenAt > $1.takenAt }
    }

    func nextMedicationReminder(after date: Date = Date()) -> (medication: Medication, date: Date)? {
        let calendar = Calendar.current

        return medications
            .filter(\.isEnabled)
            .flatMap { medication in
                medication.reminderTimes.compactMap { reminderTime in
                    let time = calendar.dateComponents([.hour, .minute], from: reminderTime)
                    guard let hour = time.hour,
                          let minute = time.minute,
                          var occurrence = calendar.date(
                            bySettingHour: hour,
                            minute: minute,
                            second: 0,
                            of: date
                          ) else { return nil }

                    if occurrence <= date {
                        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: occurrence) else {
                            return nil
                        }
                        occurrence = tomorrow
                    }
                    return (medication: medication, date: occurrence)
                }
            }
            .min { $0.date < $1.date }
    }

    func rescheduleMedicationReminders() {
        for medication in medications {
            NotificationService.shared.scheduleReminders(for: medication)
        }
    }

    // MARK: - Queries

    /// Order undone before done, then by user-controlled `sortOrder`, then by
    /// `createdAt` as a stable tiebreaker. Tuple comparison isn't available
    /// for `(Bool, Double, Date)` so we spell the comparator out.
    private func isBefore(_ a: Task, _ b: Task) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.createdAt < b.createdAt
    }

    func tasks(on day: Date) -> [Task] {
        let cal = Calendar.current
        return tasks
            .filter { $0.scheduledDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
            .sorted(by: isBefore)
    }

    var unscheduled: [Task] {
        tasks.filter { $0.scheduledDate == nil }.sorted(by: isBefore)
    }

    /// Days (normalized to start-of-day) that have at least one focus session.
    var activeDays: Set<Date> {
        let cal = Calendar.current
        return Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
    }

    /// Consecutive-day streak ending today (or yesterday).
    var currentStreak: Int {
        let cal = Calendar.current
        let active = activeDays
        var streak = 0
        var day = cal.startOfDay(for: Date())
        if !active.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
            if !active.contains(day) { return 0 }
        }
        while active.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// Focus time recorded today, in seconds.
    var focusedSecondsToday: Int {
        let cal = Calendar.current
        return sessions
            .filter { cal.isDateInToday($0.startedAt) }
            .reduce(0) { $0 + Int($1.duration) }
    }

    /// Focus blocks that ran to the end today.
    var completedBlocksToday: Int {
        let cal = Calendar.current
        return sessions.filter { $0.completed && cal.isDateInToday($0.startedAt) }.count
    }

    func recordSession(_ session: FocusSession) {
        sessions.append(session)
        if let tid = session.taskId, let idx = tasks.firstIndex(where: { $0.id == tid }) {
            tasks[idx].focusedSeconds += Int(session.duration)
        }
        save()
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var tasks: [Task]
        var sessions: [FocusSession]
        var waterIntakes: [WaterIntake]?
        var hydrationSettings: HydrationSettings?
        var medications: [Medication]?
        var medicationIntakes: [MedicationIntake]?
        var settings: FocusSettings?
    }

    func save() {
        let payload = Payload(
            tasks: tasks,
            sessions: sessions,
            waterIntakes: waterIntakes,
            hydrationSettings: hydrationSettings,
            medications: medications,
            medicationIntakes: medicationIntakes,
            settings: settings
        )
        // A read failure must never turn an existing file into an empty store.
        guard !loadFailed else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if needsRecoveryCopy { try preserveUnreadableFile() }
            // Keep the last successfully loaded/saved payload before replacing it.
            // If backup creation fails, leave the primary file untouched.
            if let lastSavedData {
                try lastSavedData.write(to: backupFileURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
            lastSavedData = data
            persistenceError = nil
        } catch {
            persistenceError = String(localized: "Changes could not be saved. Keep NotchFlow open and try again.")
                + "\n" + error.localizedDescription
        }
    }

    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return // First launch: there is no data file yet.
        } catch {
            loadFailed = true
            persistenceError = String(localized: "Your data could not be read. Saving is blocked to protect it. Check file access and reopen NotchFlow.")
                + "\n" + error.localizedDescription
            return
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
            lastSavedData = data
        } catch {
            needsRecoveryCopy = true
            do {
                try preserveUnreadableFile()
            } catch {
                persistenceError = String(localized: "The damaged data file could not be backed up. It will not be overwritten until a recovery copy can be saved.")
                    + "\n" + error.localizedDescription
            }
            // Recover a known-good previous version when one is available.
            do {
                let backupData = try Data(contentsOf: backupFileURL)
                payload = try JSONDecoder().decode(Payload.self, from: backupData)
                lastSavedData = backupData
                if !needsRecoveryCopy {
                    recoveryNotice = String(localized: "Your data was restored from the previous backup. The damaged file was preserved.")
                }
            } catch {
                if !needsRecoveryCopy {
                    recoveryNotice = String(localized: "Your data file is damaged and no valid backup is available. A recovery copy was preserved before starting an empty list.")
                }
                return
            }
        }
        isLoading = true
        defer { isLoading = false }
        tasks = payload.tasks
        sessions = payload.sessions
        waterIntakes = payload.waterIntakes ?? []
        hydrationSettings = payload.hydrationSettings ?? HydrationSettings()
        medications = payload.medications ?? []
        medicationIntakes = payload.medicationIntakes ?? []
        settings = payload.settings ?? .default
        // One-shot migration: any task with sortOrder == 0 came from a pre-reorder
        // data file. Give each one a stable value in the persisted order so the
        // first display matches what the user had, and reorders start working.
        if tasks.contains(where: { $0.sortOrder == 0 }) {
            for i in tasks.indices {
                tasks[i].sortOrder = Double(i + 1) * 1024
            }
            save()
        }
    }

    private func preserveUnreadableFile() throws {
        let recoveryURL = fileURL.deletingPathExtension()
            .appendingPathExtension("unreadable-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fileURL, to: recoveryURL)
        // Only allow overwriting the original after the copy succeeds.
        needsRecoveryCopy = false
    }
}
