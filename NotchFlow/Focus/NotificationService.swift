import Foundation
import UserNotifications
import OSLog
import Combine

/// Wraps `UNUserNotificationCenter` so the rest of the app can request
/// authorization once and post a single "focus block complete" notification
/// without dealing with the delegate dance.
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotchFlow", category: "MedicationReminders")
    @MainActor private var reminderOperation: _Concurrency.Task<Void, Never>?
    @MainActor @Published private(set) var taskReminderError: String?
    @MainActor var onOpenAIUsage: (() -> Void)?
    @MainActor var onOpenTask: ((UUID) -> Void)?
    @MainActor var onStartTask: ((UUID) -> Void)?
    private static let taskCategory = "task.start"
    private static let startAction = "task.startFocus"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        let action = UNNotificationAction(identifier: Self.startAction,
                                          title: String(localized: "Start focus"), options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.taskCategory, actions: [action], intentIdentifiers: [])
        ])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.categoryIdentifier == "ai.usage" {
            await MainActor.run { self.onOpenAIUsage?() }
            return
        }
        guard response.notification.request.content.categoryIdentifier == Self.taskCategory,
              let rawID = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: rawID) else { return }
        await MainActor.run {
            if response.actionIdentifier == Self.startAction { self.onStartTask?(id) }
            else if response.actionIdentifier == UNNotificationDefaultActionIdentifier { self.onOpenTask?(id) }
        }
    }

    /// Replace task reminders in the same serial queue as medication operations.
    /// A snapshot ensures edits, completion, deletion and recurrence stay ordered.
    @MainActor
    func scheduleTaskReminders(for tasks: [Task]) {
        enqueueReminderOperation { [self] in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
                $0.hasPrefix("task.reminder.")
            })
            taskReminderError = nil
            let future = tasks.filter { $0.reminderDate() != nil }
            guard !future.isEmpty else { return }
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    taskReminderError = String(localized: "Task alerts are blocked. Allow notifications for NotchFlow in System Settings.")
                    return
                }
                for task in future {
                    // Permission prompts can take long enough for a reminder to expire.
                    guard let date = task.reminderDate(), let start = task.scheduledStart else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = String(localized: "Activity reminder")
                    content.body = String(localized: "\(task.title) starts at \(start.formatted(date: .omitted, time: .shortened)).")
                    content.sound = .default
                    content.categoryIdentifier = Self.taskCategory
                    content.userInfo = ["taskID": task.id.uuidString]
                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    try await center.add(UNNotificationRequest(identifier: "task.reminder.\(task.id)", content: content, trigger: trigger))
                }
            } catch {
                logger.error("Task reminder scheduling failed: \(error.localizedDescription, privacy: .public)")
                taskReminderError = String(localized: "Task alerts could not be scheduled. Try again.")
            }
        }
    }

    /// Ask the user for notification permission. The system only shows the
    /// prompt once per install; subsequent calls return the current grant
    /// state without re-prompting, so it's safe to call from app launch and
    /// again from each focus block start.
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Whether macOS currently lets NotchFlow post notifications. `nil` while
    /// the user hasn't been asked yet.
    func isAuthorized() async -> Bool? {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return nil
        case .denied: return false
        default: return true
        }
    }

    @MainActor
    func scheduleReminders(for medication: Medication) {
        enqueueReminderOperation { [self] in
            await removeReminders(for: medication.id)
            await addReminders(for: medication)
        }
    }

    // Wait for every earlier operation, including notification additions.
    // Rapid edits, disabling and deletion must preserve the caller's order.
    @MainActor
    private func enqueueReminderOperation(_ operation: @escaping @MainActor () async -> Void) {
        let previous = reminderOperation
        reminderOperation = _Concurrency.Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    @MainActor
    private func addReminders(for medication: Medication) async {
        guard medication.isEnabled else { return }

        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
        } catch {
            logger.error("Medication reminder authorization failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        for (index, time) in medication.sortedReminderTimes.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Medication reminder")
            content.body = medication.dosage.isEmpty
                ? String(localized: "Time to take \(medication.name).")
                : String(localized: "Time to take \(medication.name) — \(medication.dosage).")
            content.sound = .default

            let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: timeComponents,
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(medicationID: medication.id, index: index),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("Medication reminder scheduling failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    func cancelReminders(for medicationID: UUID) {
        enqueueReminderOperation { [self] in
            await removeReminders(for: medicationID)
        }
    }

    @MainActor
    private func removeReminders(for medicationID: UUID) async {
        let prefix = reminderPrefix(medicationID: medicationID)
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func reminderPrefix(medicationID: UUID) -> String {
        "medication.\(medicationID.uuidString)."
    }

    private func reminderIdentifier(medicationID: UUID, index: Int) -> String {
        "\(reminderPrefix(medicationID: medicationID))\(index)"
    }

    func postAIUsageAlert(_ alert: AIUsageAlert) {
        let content = UNMutableNotificationContent()
        switch alert.kind {
        case .threshold(let percent):
            content.title = String(localized: "AI usage limit")
            content.body = "\(alert.provider.name) · \(alert.window.title.localized): \(percent)%"
        case .reset:
            content.title = String(localized: "AI limit renewed")
            content.body = "\(alert.provider.name) · \(alert.window.title.localized)"
        }
        content.categoryIdentifier = "ai.usage"
        content.sound = alert.sound ? .default : nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "ai.usage.\(alert.provider.rawValue).\(alert.window.id).\(UUID())",
            content: content, trigger: nil), withCompletionHandler: nil)
    }

    /// Post the "focus block complete" notification immediately. Caller
    /// checks `FocusSettings.notificationsEnabled` before invoking.
    func postFocusComplete(taskTitle: String?) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Focus block complete")
        if let task = taskTitle, !task.isEmpty {
            content.body = String(localized: "You finished \u{201C}\(task)\u{201D}. Time for a break.")
        } else {
            content.body = String(localized: "Time for a break.")
        }
        // Silent on purpose: the focus timer plays its own chime when the
        // "Play sound" setting is on, so a notification sound would double it
        // (and ignore that setting when it is off).
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "focus.complete.\(UUID().uuidString)",
            content: content,
            trigger: nil)   // deliver immediately
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
