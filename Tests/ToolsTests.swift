import AppKit

@main
struct ToolsTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notchflow-tools-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("data.json")
        let store = Store(fileURL: file, taskReminderScheduler: { _ in })
        precondition(store.addQuickNote(" \n ") == nil)
        let text = "Review design\n" + String(repeating: "Details ", count: 100)
        let id = store.addQuickNote(text)!
        store.convertQuickNote(id)
        precondition(store.tasks.count == 1 && store.tasks[0].title == "Review design")
        precondition(store.tasks[0].scheduledDate == nil)
        precondition(store.quickNotes.first?.text == text.trimmingCharacters(in: .whitespacesAndNewlines), "Converting must preserve notes longer than the task note limit")
        store.updateQuickNote(id, text: String(repeating: "a", count: QuickNote.limit + 100))
        precondition(store.quickNotes[0].text.count == QuickNote.limit)
        let reloaded = Store(fileURL: file, taskReminderScheduler: { _ in })
        precondition(reloaded.quickNotes == store.quickNotes)
        reloaded.removeQuickNote(id)
        precondition(Store(fileURL: file, taskReminderScheduler: { _ in }).quickNotes.isEmpty)
        let settings = try JSONDecoder().decode(FocusSettings.self, from: Data("{}".utf8))
        precondition(settings.commandPaletteHotkeyEnabled && settings.upcomingEventEnabled && settings.upcomingEventLeadMinutes == 10)
        let now = Date()
        let event = UpcomingEvent(title: "Meeting", start: now.addingTimeInterval(600), end: now.addingTimeInterval(4200), meetingURL: nil)
        precondition(event.isCompactDue(at: now, enabled: true, leadMinutes: 10))
        precondition(!event.isCompactDue(at: now, enabled: true, leadMinutes: 5))
        precondition(!event.isCompactDue(at: now, enabled: false, leadMinutes: 60))
        precondition(!event.isCompactDue(at: now.addingTimeInterval(901), enabled: true, leadMinutes: 10))
        let command = PaletteCommand(id: "notes", title: "Quick notes", symbol: "note.text", action: .notes)
        precondition(command.matches("notas", localizedTitle: "Notas rápidas"))
        precondition(command.matches("rapidas notas", localizedTitle: "Notas rápidas"))
        precondition(!command.matches("clipboard", localizedTitle: "Notas rápidas"))

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let defaults = UserDefaults(suiteName: "notchflow-test-\(UUID())")!
        let clipboard = ClipboardMonitor(pasteboard: pasteboard, defaults: defaults, start: false)
        pasteboard.setString("Before enable", forType: .string)
        clipboard.setEnabled(true)
        clipboard.poll()
        precondition(clipboard.entries.isEmpty, "Enabling must not import the existing clipboard")
        pasteboard.clearContents(); pasteboard.setString("Private fixture", forType: .string)
        clipboard.poll()
        precondition(clipboard.entries.first?.text == "Private fixture")
        pasteboard.clearContents()
        pasteboard.setString("Secret fixture", forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        clipboard.poll()
        precondition(clipboard.entries.count == 1, "Concealed copies must not enter history")
        clipboard.copy(clipboard.entries[0]); clipboard.poll()
        precondition(clipboard.entries.count == 1)
        clipboard.setEnabled(false)
        precondition(clipboard.entries.isEmpty)

        let source = directory.appendingPathComponent("original.txt")
        let other = directory.appendingPathComponent("second.txt")
        try Data("original".utf8).write(to: source)
        try Data("second".utf8).write(to: other)
        let shelf = FileShelf(directory: directory.appendingPathComponent("Shelf"))
        shelf.importFiles([source]); shelf.importFiles([other])
        let deadline = Date().addingTimeInterval(10)
        while shelf.busy && Date() < deadline { try await _Concurrency.Task.sleep(for: .milliseconds(20)) }
        precondition(shelf.files.count == 2 && !shelf.busy, "Consecutive drops must queue instead of dropping files")
        let original = try Data(contentsOf: source)
        precondition(original == Data("original".utf8))
        precondition(shelf.files.allSatisfy { $0.url != source && $0.url != other })
        precondition(FileShelf(directory: shelf.directory).files.count == 2)
        print("PASS: quick notes, migration, task conversion, event boundaries, palette search, private clipboard and queued file imports")
    }
}
