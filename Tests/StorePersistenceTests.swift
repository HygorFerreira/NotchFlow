import Foundation

/// Standalone regression checks using the production Store and temporary files.
/// Run with scripts/test-store.sh (no Xcode project test target required).
@main
struct StorePersistenceTests {
    @MainActor
    static func main() throws {
        func makeStore(fileURL: URL) -> Store {
            Store(fileURL: fileURL, taskReminderScheduler: { _ in })
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NotchFlowTests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let url = root.appendingPathComponent("normal/data.json")
        let store = makeStore(fileURL: url)
        precondition(store.persistenceError == nil)
        store.add(title: "First")
        let firstData = try Data(contentsOf: url)
        store.add(title: "Second")
        precondition(tryData(store.backupFileURL) == firstData)
        let reloaded = makeStore(fileURL: url)
        precondition(reloaded.tasks.map(\.title) == ["First", "Second"])

        // A backup failure must not overwrite the primary file.
        let currentData = try Data(contentsOf: url)
        try fm.removeItem(at: store.backupFileURL)
        try fm.createDirectory(at: store.backupFileURL, withIntermediateDirectories: true)
        store.add(title: "Unsaved")
        precondition(store.persistenceError != nil)
        precondition(tryData(url) == currentData)
        try fm.removeItem(at: store.backupFileURL)
        store.save()
        precondition(store.persistenceError == nil)
        precondition(makeStore(fileURL: url).tasks.count == 3)

        // Invalid JSON is preserved, and the previous valid version is loaded.
        let damaged = Data("invalid JSON".utf8)
        try damaged.write(to: url)
        let recovered = makeStore(fileURL: url)
        precondition(recovered.tasks.count == 2)
        precondition(recovered.recoveryNotice != nil)
        let copies = try fm.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("unreadable-") }
        precondition(copies.count == 1 && tryData(copies[0]) == damaged)
        recovered.save()
        precondition(makeStore(fileURL: url).tasks.count == 2)

        // Failed recovery-copy creation blocks replacement of the damaged file.
        let protectedDirectory = root.appendingPathComponent("protected")
        try fm.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        let protectedURL = protectedDirectory.appendingPathComponent("data.json")
        try damaged.write(to: protectedURL)
        try firstData.write(to: protectedURL.appendingPathExtension("backup"))
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: protectedDirectory.path)
        let protectedStore = makeStore(fileURL: protectedURL)
        protectedStore.save()
        precondition(protectedStore.persistenceError != nil)
        precondition(protectedStore.tasks.count == 1)
        precondition(tryData(protectedURL) == damaged)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protectedDirectory.path)
        protectedStore.save()
        precondition(protectedStore.persistenceError == nil)
        precondition(makeStore(fileURL: protectedURL).tasks.count == 1)

        // Without a valid backup the original remains available for recovery.
        let noBackupURL = root.appendingPathComponent("no-backup.json")
        try damaged.write(to: noBackupURL)
        let emptyRecovery = makeStore(fileURL: noBackupURL)
        precondition(emptyRecovery.tasks.isEmpty && emptyRecovery.recoveryNotice != nil)
        precondition(tryData(noBackupURL) == damaged)

        // A read error is distinct from a missing first-launch file.
        let directoryURL = root.appendingPathComponent("data-directory")
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let unreadable = makeStore(fileURL: directoryURL)
        precondition(unreadable.persistenceError != nil && !unreadable.canRetrySave)
        unreadable.add(title: "Must not overwrite")
        var isDirectory: ObjCBool = false
        precondition(fm.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) && isDirectory.boolValue)

        // Write failure is visible, retains memory, and can be retried.
        // Start as a new store while the directory exists, then obstruct writes.
        let retryParent = root.appendingPathComponent("retry")
        try fm.createDirectory(at: retryParent, withIntermediateDirectories: true)
        let retryURL = retryParent.appendingPathComponent("data.json")
        let retryStore = makeStore(fileURL: retryURL)
        try fm.removeItem(at: retryParent)
        try Data("file".utf8).write(to: retryParent)
        retryStore.add(title: "Retained")
        precondition(retryStore.persistenceError != nil && retryStore.tasks.count == 1)
        try fm.removeItem(at: retryParent)
        retryStore.save()
        precondition(retryStore.persistenceError == nil)
        precondition(makeStore(fileURL: retryURL).tasks.first?.title == "Retained")
        print("PASS: round trip, backup, failed backup protection, corrupt recovery, read protection, write retry")
    }

    private static func tryData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
