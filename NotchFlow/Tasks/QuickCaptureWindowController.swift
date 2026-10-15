import AppKit
import SwiftUI

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class QuickCaptureWindowController: NSObject, NSWindowDelegate {
    private let store: Store
    private var panel: NSPanel?

    init(store: Store) { self.store = store }

    func show() {
        if panel == nil {
            let panel = QuickCapturePanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                                          styleMask: [.titled, .closable, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
            panel.title = String(localized: "Quick capture")
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: QuickCaptureView(onClose: { [weak panel] in panel?.close() })
                .safeAreaInset(edge: .bottom, spacing: 0) { StorePersistenceBanner() }
                .environmentObject(store))
            panel.delegate = self
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                             y: frame.midY - panel.frame.height / 2))
            }
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { panel = nil }
}

struct QuickCaptureView: View {
    @EnvironmentObject private var store: Store
    let onClose: () -> Void
    @State private var title = ""
    @State private var project = ""
    @State private var tags = ""
    @State private var recurrence = TaskRecurrence()
    @State private var date = Date()
    @State private var unscheduled = false
    @State private var startTime: Date?
    @State private var endTime: Date?
    @State private var reminderMinutesBefore: Int?
    @State private var didAdd = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowPageHeading(title: didAdd ? "Task added" : "Quick capture",
                            subtitle: "Make room for your next idea", symbol: "square.and.pencil")
            if didAdd {
                Text("The task is in memory. Retry saving before closing NotchFlow.")
                    .foregroundStyle(.secondary)
            } else {
                TextField("Task title", text: $title)
                    .textFieldStyle(FlowTextFieldStyle())
                    .focused($titleFocused)
                    .onSubmit { addTask() }
                    .onChange(of: title) { _, value in title = String(value.prefix(Task.titleLimit)) }
                HStack {
                    Toggle("Unscheduled", isOn: $unscheduled)
                        .disabled(recurrence.frequency != .none)
                    if !unscheduled { DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden() }
                }
                TaskScheduleView(date: Binding(
                    get: { unscheduled ? nil : date },
                    set: { value in if let value { date = value; unscheduled = false } }),
                    startTime: $startTime, endTime: $endTime, reminderMinutesBefore: $reminderMinutesBefore)
                .onChange(of: unscheduled) { _, value in
                    if value { startTime = nil; endTime = nil; reminderMinutesBefore = nil }
                }
                TaskOptionsView(project: $project, tagsText: $tags, recurrence: $recurrence)
                    .onChange(of: recurrence.frequency) { _, value in
                        if value != .none { unscheduled = false }
                    }
            }
            HStack {
                Text("⌘⇧N").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(didAdd ? "Close" : "Cancel", action: onClose).keyboardShortcut(.cancelAction)
                    .buttonStyle(FlowButtonStyle())
                if !didAdd {
                    Button("Add", action: addTask)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(FlowButtonStyle(prominent: true))
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !recurrence.isValid || !Task.isValidTimeRange(start: startTime, end: endTime))
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.windowBackground)
        .flowAppearance()
        .onAppear { titleFocused = true }
        .onChange(of: store.persistenceError) { _, error in
            if didAdd && error == nil { onClose() }
        }
    }

    private func addTask() {
        guard !didAdd, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, recurrence.isValid, Task.isValidTimeRange(start: startTime, end: endTime) else { return }
        store.add(title: title, date: unscheduled ? nil : date, project: project,
                  tags: Task.normalizedTags(tags), recurrence: recurrence,
                  startTime: startTime, endTime: endTime, reminderMinutesBefore: reminderMinutesBefore)
        store.selectedProject = nil
        store.selectedTag = nil
        didAdd = true
        if store.persistenceError == nil { onClose() }
    }
}
