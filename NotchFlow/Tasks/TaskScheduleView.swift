import SwiftUI
import AppKit

struct TaskScheduleView: View {
    @Binding var date: Date?
    @Binding var startTime: Date?
    @Binding var endTime: Date?
    @Binding var reminderMinutesBefore: Int?
    @ObservedObject private var notifications = NotificationService.shared
    @State private var permissionDenied = false

    private var startDate: Date? {
        Task(title: "", scheduledDate: date, startTime: startTime).scheduledStart
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Set start time", isOn: Binding(
                    get: { startTime != nil },
                    set: { enabled in
                        if enabled {
                            if date == nil { date = Date() }
                            startTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                            reminderMinutesBefore = 0
                        } else {
                            startTime = nil
                            endTime = nil
                            reminderMinutesBefore = nil
                        }
                    }))
                if startTime != nil {
                    DatePicker("Start time", selection: Binding(
                        get: { startTime ?? Date() }, set: { startTime = $0 }),
                        displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            if startTime != nil {
                HStack {
                    Toggle("Set end time", isOn: Binding(
                        get: { endTime != nil },
                        set: { enabled in
                            endTime = enabled
                                ? Calendar.current.date(byAdding: .hour, value: 1, to: startTime ?? Date())
                                : nil
                        }))
                    if endTime != nil {
                        DatePicker("End time", selection: Binding(
                            get: { endTime ?? Date() }, set: { endTime = $0 }),
                            displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                if !Task.isValidTimeRange(start: startTime, end: endTime) {
                    Text("End time must be after start time on the same day.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("Alert", selection: $reminderMinutesBefore) {
                    Text("No alert").tag(nil as Int?)
                    Text("At start time").tag(0 as Int?)
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text("\(minutes) minutes before").tag(minutes as Int?)
                    }
                }
                if let startDate, let minutes = reminderMinutesBefore,
                   startDate.addingTimeInterval(-Double(minutes) * 60) <= Date() {
                    Text("This alert time has already passed. Choose a later time to receive a notification.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if permissionDenied || notifications.taskReminderError != nil {
                    Text(notifications.taskReminderError ?? String(localized: "Task alerts are blocked. Allow notifications for NotchFlow in System Settings."))
                        .font(.caption).foregroundStyle(.orange)
                    Button("Open notification settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .font(.system(size: 12))
        .task { permissionDenied = await notifications.isAuthorized() == false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            _Concurrency.Task { permissionDenied = await notifications.isAuthorized() == false }
        }
    }
}

struct TaskReminderStatusView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var notifications = NotificationService.shared

    var body: some View {
        if let error = notifications.taskReminderError {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button("Retry alerts") { store.rescheduleTaskReminders() }
                    Button("Open notification settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .font(.caption)
            }
        }
    }
}
