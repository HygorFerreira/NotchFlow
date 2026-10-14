import Foundation

@main
struct ProductivityTests {
    @MainActor
    static func main() throws {
        func makeStore(fileURL: URL) -> Store {
            Store(fileURL: fileURL, taskReminderScheduler: { _ in })
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Recife")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NotchFlowProductivity-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let store = makeStore(fileURL: root.appendingPathComponent("data.json"))

        let navigation = WorkspaceNavigation()
        precondition(navigation.destination == .tasks && navigation.visited == [.tasks])
        navigation.select(.water)
        navigation.select(.ai)
        navigation.select(.tasks)
        precondition(navigation.destination == .tasks && navigation.visited == [.tasks, .water, .ai])
        navigation.select(.tasks)
        precondition(navigation.visited.count == 3, "Revisiting screens must retain their identities without adding duplicates")
        print("PASS: workspace destinations, lazy visits and stable navigation identities")

        // Missing new keys must decode existing user files without resetting them.
        let oldTask = Task(title: "Legacy", sortOrder: 1024)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldTask)) as! [String: Any]
        for key in ["project", "tags", "recurrence", "recurrenceParentID", "completedAt"] { legacy.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(Task.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decoded.project.isEmpty && decoded.tags.isEmpty && decoded.recurrence.frequency == .none)
        var legacyCompleted = decoded
        legacyCompleted.isDone = true
        legacyCompleted.completedAt = nil
        let legacyStore = makeStore(fileURL: root.appendingPathComponent("legacy.json"))
        legacyStore.tasks = [legacyCompleted]
        legacyStore.update(legacyCompleted)
        precondition(legacyStore.tasks[0].completedAt == nil, "Editing an old completed task must not invent a completion date")
        let legacySettings = try JSONDecoder().decode(FocusSettings.self, from: Data("{}".utf8))
        precondition(legacySettings.quickCaptureHotkeyEnabled && legacySettings.weeklyGoalMinutes == 300)
        let extremeSettings = try JSONDecoder().decode(FocusSettings.self,
            from: Data("{\"focusMinutes\":9223372036854775807}".utf8))
        precondition(extremeSettings.focusMinutes == 180)

        // A detail draft must not overwrite focus earned after it was opened.
        let editStore = makeStore(fileURL: root.appendingPathComponent("edits.json"))
        editStore.add(title: "Original")
        var draft = editStore.tasks[0]
        editStore.recordSession(FocusSession(taskId: draft.id, startedAt: date(6),
            endedAt: date(6).addingTimeInterval(120), completed: false))
        draft.title = "  Edited  "
        draft.notes = String(repeating: "a", count: Task.notesLimit + 20)
        draft.estimateMinutes = Int.max
        editStore.update(draft)
        precondition(editStore.tasks[0].focusedSeconds == 120)
        precondition(editStore.tasks[0].title == "Edited")
        precondition(editStore.tasks[0].notes.count == Task.notesLimit)
        precondition(editStore.tasks[0].estimateMinutes == 180)
        precondition(makeStore(fileURL: editStore.dataFileURL).tasks[0].focusedSeconds == 120)
        let beforeDrag = editStore.tasks
        editStore.moveTasks(in: [], from: IndexSet(integer: 0), to: 0)
        editStore.moveTasks(in: beforeDrag, from: IndexSet(integer: 9), to: 0)
        editStore.moveTasks(in: beforeDrag, from: IndexSet(integer: 0), to: 9)
        precondition(editStore.tasks == beforeDrag, "Stale drag indices must not crash or mutate tasks")

        // Accessible reordering uses the same order as dragging and respects group boundaries.
        let reorderStore = makeStore(fileURL: root.appendingPathComponent("accessible-order.json"))
        for title in ["First", "Second", "Third", "Completed"] { reorderStore.add(title: title, date: nil) }
        reorderStore.toggleDone(reorderStore.tasks[3])
        let third = reorderStore.unscheduled[2]
        reorderStore.moveTask(third, in: reorderStore.unscheduled, by: -1)
        precondition(reorderStore.unscheduled.map(\.title) == ["First", "Third", "Second", "Completed"])
        reorderStore.moveTask(third, in: reorderStore.unscheduled, by: 1)
        precondition(reorderStore.unscheduled.map(\.title) == ["First", "Second", "Third", "Completed"])
        let beforeInvalidMove = reorderStore.tasks
        reorderStore.moveTask(reorderStore.unscheduled[0], in: reorderStore.unscheduled, by: -1)
        reorderStore.moveTask(third, in: reorderStore.unscheduled, by: 1)
        reorderStore.moveTask(third, in: [], by: -1)
        reorderStore.moveTask(third, in: reorderStore.unscheduled, by: Int.max)
        precondition(reorderStore.tasks == beforeInvalidMove)
        precondition(makeStore(fileURL: reorderStore.dataFileURL).unscheduled == reorderStore.unscheduled)
        print("PASS: accessible reorder direction, boundaries, completion groups, invalid offsets and persistence")

        // Native undo restores the live task, persists it, and re-arms reminders.
        var undoSchedules: [[Task]] = []
        let undoStore = Store(fileURL: root.appendingPathComponent("undo.json"),
                              taskReminderScheduler: { undoSchedules.append($0) })
        undoStore.add(title: "Before")
        undoStore.add(title: "Restore me", project: "Work", tags: ["review"])
        let staleDraft = undoStore.tasks[1]
        undoStore.recordSession(FocusSession(taskId: staleDraft.id, startedAt: date(6),
            endedAt: date(6).addingTimeInterval(90), completed: false))
        let liveTask = undoStore.tasks[1]
        undoStore.add(title: "After")
        let manager = UndoManager()
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        undoStore.delete(staleDraft, undoManager: manager)
        manager.endUndoGrouping()
        precondition(manager.canUndo && !undoStore.tasks.contains { $0.id == liveTask.id })
        undoStore.add(title: "Unrelated new task")
        manager.undo()
        precondition(undoStore.tasks[1] == liveTask, "Undo must restore live focus time and metadata, not the stale draft")
        precondition(undoStore.tasks.last?.title == "Unrelated new task", "Undo must preserve unrelated edits")
        precondition(undoSchedules.last == undoStore.tasks, "Undo must reschedule task reminders")
        precondition(makeStore(fileURL: undoStore.dataFileURL).tasks == undoStore.tasks, "Undo must persist the restored task")
        precondition(manager.canRedo)
        manager.redo()
        precondition(!undoStore.tasks.contains { $0.id == liveTask.id })
        manager.undo()
        precondition(undoStore.tasks.filter { $0.id == liveTask.id }.count == 1)
        var deactivations = 0
        undoStore.onTaskDeactivated = { _, _ in deactivations += 1 }
        let absent = Task(title: "Absent")
        undoStore.delete(absent, undoManager: manager)
        precondition(deactivations == 0, "Deleting an absent task must be a no-op")
        print("PASS: native deletion undo/redo, live metadata, unrelated edits, reminder rescheduling and persistence")

        precondition(Task.normalizedTags("#Swift, swift, Work, , #work ") == ["swift", "work"])
        let daily = TaskRecurrence(frequency: .daily)
        let weekly = TaskRecurrence(frequency: .weekly)
        let weekdays = TaskRecurrence(frequency: .custom, weekdays: [2, 4, 6])
        precondition(daily.nextDate(after: date(6), calendar: calendar) == date(7, 0))
        precondition(weekly.nextDate(after: date(6), calendar: calendar) == date(13, 0))
        precondition(weekdays.nextDate(after: date(9), calendar: calendar) == date(12, 0))
        precondition(!TaskRecurrence(frequency: .custom).isValid)
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstStart = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let dstNext = daily.nextDate(after: dstStart, calendar: dstCalendar)!
        precondition(dstNext.timeIntervalSince(dstStart) == 23 * 3600)

        // Start times use the scheduled day and the chosen local clock time.
        let scheduleDay = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let clock = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date())!
        var planned = Task(title: "Scheduled", scheduledDate: scheduleDay,
                           startTime: clock, reminderMinutesBefore: 10)
        let expectedStart = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: scheduleDay)!
        precondition(planned.scheduledStart == expectedStart)
        precondition(planned.reminderDate(after: expectedStart.addingTimeInterval(-3600)) == expectedStart.addingTimeInterval(-600))
        precondition(planned.reminderDate(after: expectedStart) == nil)
        planned.isDone = true
        precondition(planned.reminderDate(after: expectedStart.addingTimeInterval(-3600)) == nil)
        planned.isDone = false
        planned.scheduledDate = nil
        precondition(planned.scheduledStart == nil && planned.reminderDate() == nil)
        planned.scheduledDate = scheduleDay
        planned.reminderMinutesBefore = nil
        precondition(planned.reminderDate() == nil)
        planned.reminderMinutesBefore = 0
        precondition(planned.reminderDate(after: expectedStart.addingTimeInterval(-1)) == expectedStart)
        let scheduleReload = try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(planned))
        precondition(scheduleReload.startTime == clock && scheduleReload.reminderMinutesBefore == 0)
        precondition(decoded.startTime == nil && decoded.reminderMinutesBefore == nil)

        // Store mutations keep the notification scheduler informed, including recurrence.
        var scheduledSnapshots: [[Task]] = []
        let reminderStore = Store(fileURL: root.appendingPathComponent("reminders.json"),
                                  taskReminderScheduler: { scheduledSnapshots.append($0) })
        reminderStore.add(title: "Alert", date: scheduleDay, recurrence: daily,
                          startTime: clock, reminderMinutesBefore: 10)
        precondition(scheduledSnapshots.count == 1 && scheduledSnapshots.last?.first?.reminderDate() != nil)
        var changed = reminderStore.tasks[0]
        changed.reminderMinutesBefore = 30
        reminderStore.update(changed)
        precondition(scheduledSnapshots.last?.first?.reminderMinutesBefore == 30)
        reminderStore.toggleDone(reminderStore.tasks[0])
        precondition(scheduledSnapshots.last?.first?.reminderDate() == nil)
        precondition(reminderStore.tasks[1].startTime == clock && reminderStore.tasks[1].reminderMinutesBefore == 30)
        reminderStore.delete(reminderStore.tasks[1])
        precondition(scheduledSnapshots.last?.count == 1)

        // Completion creates an independent occurrence with inherited metadata.
        let today = Calendar.current.startOfDay(for: Date())
        store.add(title: "Recurring", date: today, project: " Work ", tags: ["#Swift", "swift"], recurrence: daily)
        let original = store.tasks[0]
        store.toggleDone(original)
        precondition(store.tasks.count == 2 && store.tasks[0].completedAt != nil)
        let successor = store.tasks[1]
        precondition(successor.recurrenceParentID == original.id && !successor.isDone)
        precondition(successor.project == "Work" && successor.tags == ["swift"] && successor.focusedSeconds == 0)
        precondition(successor.scheduledDate == daily.nextDate(after: today))
        store.toggleDone(store.tasks[0])
        store.toggleDone(store.tasks[0])
        precondition(store.tasks.count == 2, "Undo and redo must not duplicate occurrences")
        var edited = successor
        edited.isDone = true
        store.update(edited)
        precondition(store.tasks.count == 3, "Completing in the detail editor must also repeat")
        precondition(store.tasks[1].completedAt != nil)
        let reloaded = makeStore(fileURL: store.dataFileURL)
        precondition(reloaded.tasks[2].recurrence == daily && reloaded.tasks[2].project == "Work")

        // Late completion skips missed days while preserving the weekly weekday.
        let past = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        store.add(title: "Overdue", date: past, recurrence: weekly)
        let overdue = store.tasks.last!
        store.toggleDone(overdue)
        let next = store.tasks.last!
        precondition(next.scheduledDate! >= today)
        precondition(Calendar.current.component(.weekday, from: next.scheduledDate!) == Calendar.current.component(.weekday, from: past))

        store.add(title: "Personal task", date: nil, project: "Personal", tags: ["home"])
        store.selectedProject = "Personal"
        precondition(store.filteredTasks(store.tasks).map(\.title) == ["Personal task"])
        store.selectedTag = "swift"
        precondition(store.filteredTasks(store.tasks).isEmpty)
        store.selectedProject = "Work"
        precondition(store.filteredTasks(store.tasks).count == 3)
        precondition(store.projects == ["Personal", "Work"] && store.allTags == ["home", "swift"])

        // Midnight and week-boundary sessions are split without double counting.
        var completed = Task(title: "Finished", project: "Work")
        completed.isDone = true
        completed.completedAt = date(6)
        let deletedID = UUID()
        let sessions = [
            FocusSession(taskId: completed.id, startedAt: date(5, 23, 50), endedAt: date(6, 0, 10), completed: true),
            FocusSession(taskId: nil, startedAt: date(4, 23, 50), endedAt: date(5, 0, 10), completed: true),
            FocusSession(taskId: deletedID, startedAt: date(6, 13), endedAt: date(6, 13, 30), completed: false),
            FocusSession(taskId: nil, startedAt: date(12, 0), endedAt: date(12, 1), completed: true)
        ]
        let summary = WeeklySummary(date: date(6), tasks: [completed, decoded], sessions: sessions, calendar: calendar)
        precondition(summary.days.count == 7)
        precondition(summary.totalSeconds == 3600)
        precondition(summary.days[0].seconds == 1200 && summary.days[1].seconds == 2400)
        precondition(summary.previousWeekSeconds == 600)
        precondition(summary.completedTasks == 1 && summary.completedBlocks == 2)
        precondition(summary.taskTimes.count == 3)
        precondition(summary.taskTimes.reduce(0) { $0 + $1.seconds } == summary.totalSeconds)
        precondition(summary.taskTimes.first?.id == deletedID)
        // Hydration survives relaunch, keeps original serving sizes and respects local midnight.
        let waterURL = root.appendingPathComponent("water.json")
        try Data("{\"tasks\":[],\"sessions\":[]}".utf8).write(to: waterURL)
        let waterStore = makeStore(fileURL: waterURL)
        precondition(waterStore.waterIntakes.isEmpty && waterStore.hydrationSettings.goalMilliliters == 2000)
        var waterSettings = HydrationSettings()
        waterSettings.glassMilliliters = 300
        waterSettings.bottleMilliliters = 1000
        waterStore.updateHydrationSettings(waterSettings)
        waterStore.recordWater(at: date(8, 23, 59))
        waterSettings.container = .bottle
        waterStore.updateHydrationSettings(waterSettings)
        waterStore.recordWater(at: date(9, 0, 1))
        waterStore.recordWater(at: date(9, 14))
        precondition(waterStore.waterTotal(on: date(8), calendar: calendar) == 300)
        precondition(waterStore.waterTotal(on: date(9), calendar: calendar) == 2000)
        precondition(waterStore.waterTotal(on: date(10), calendar: calendar) == 0)
        waterSettings.remindersEnabled = true
        waterSettings.reminderIntervalMinutes = 90
        waterSettings.bottleMilliliters = 750
        waterStore.updateHydrationSettings(waterSettings)
        let waterReload = makeStore(fileURL: waterURL)
        precondition(waterReload.hydrationSettings.remindersEnabled && waterReload.hydrationSettings.reminderIntervalMinutes == 90)
        precondition(waterReload.hydrationSettings.bottleMilliliters == 750 && waterReload.hydrationSettings.container == .bottle)
        precondition(waterReload.waterTotal(on: date(9), calendar: calendar) == 2000)
        let lastWater = waterReload.waterIntakes(on: date(9), calendar: calendar).first!
        precondition(lastWater.container == .bottle && lastWater.recordedAt == date(9, 14))
        waterReload.deleteWaterIntake(lastWater)
        precondition(makeStore(fileURL: waterURL).waterTotal(on: date(9), calendar: calendar) == 1000)
        waterSettings.bottleMilliliters = -1
        waterSettings.goalMilliliters = Int.max
        waterReload.updateHydrationSettings(waterSettings)
        precondition(waterReload.hydrationSettings.bottleMilliliters == 50 && waterReload.hydrationSettings.goalMilliliters == 10000)
        precondition(HydrationSettings.capacity(from: "0,75", inLiters: true) == 750)
        precondition(HydrationSettings.capacity(from: "1.5", inLiters: true) == 1500)
        precondition(HydrationSettings.capacity(from: " 250 ", inLiters: false) == 250)
        for invalid in ["", "abc", "1L", "1.2.3", "-2", "NaN", "3001", "49", "0.5"] {
            precondition(HydrationSettings.capacity(from: invalid, inLiters: false) == nil)
        }
        precondition(HydrationSettings.capacity(from: "0,050", inLiters: true) == 50)
        precondition(HydrationSettings.capacity(from: "3", inLiters: true) == 3000)
        precondition(HydrationSettings.capacity(from: "3.001", inLiters: true) == nil)
        let hydrationDefaults = try JSONDecoder().decode(HydrationSettings.self, from: Data("{}".utf8))
        precondition(hydrationDefaults.servingMilliliters == 250)
        precondition(!hydrationDefaults.remindersEnabled && hydrationDefaults.reminderIntervalMinutes == 60)
        let invalidInterval = try JSONDecoder().decode(HydrationSettings.self, from: Data("{\"reminderIntervalMinutes\":0}".utf8))
        precondition(invalidInterval.reminderIntervalMinutes == 15)
        var reminderSettings = HydrationSettings()
        reminderSettings.remindersEnabled = true
        precondition(!reminderSettings.isReminderDue(at: date(9, 9, 59), since: date(9, 9), totalMilliliters: 0, calendar: calendar))
        precondition(reminderSettings.isReminderDue(at: date(9, 10), since: date(9, 9), totalMilliliters: 0, calendar: calendar))
        precondition(!reminderSettings.isReminderDue(at: date(9, 10), since: date(9, 9, 30), totalMilliliters: 0, calendar: calendar))
        precondition(!reminderSettings.isReminderDue(at: date(9, 10), since: date(9, 9), totalMilliliters: 2000, calendar: calendar))
        precondition(!reminderSettings.isReminderDue(at: date(9, 22), since: date(9, 20), totalMilliliters: 0, calendar: calendar))
        precondition(!reminderSettings.isReminderDue(at: date(9, 7), since: date(9, 5), totalMilliliters: 0, calendar: calendar))
        reminderSettings.remindersEnabled = false
        precondition(!reminderSettings.isReminderDue(at: date(9, 10), since: date(9, 9), totalMilliliters: 0, calendar: calendar))
        print("PASS: hydration reminder interval, quiet hours, goal and disabled state")
        print("PASS: hydration migration, glass and bottle settings, immutable volumes, daily boundaries, persistence and removal")
        print("PASS: legacy decoding, metadata, recurrence, undo/redo, overdue dates, DST, filters, weekly totals and boundaries")
    }
}
