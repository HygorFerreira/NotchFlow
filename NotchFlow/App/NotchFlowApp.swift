import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

@main
struct NotchFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var focusMenu = FocusMenuState.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @ObservedObject private var store = AppDelegate.sharedStore
    @ObservedObject private var notifications = NotificationService.shared

    var body: some Scene {
        MenuBarExtra {
            if notifications.taskReminderError != nil {
                Button("Task alerts need attention…") { appDelegate.showTasksWindow() }
                Divider()
            }
            if store.persistenceError != nil || store.recoveryNotice != nil {
                Button("Data needs attention…") { appDelegate.showTasksWindow() }
                Divider()
            }
            Button("Open Tasks…") { appDelegate.showTasksWindow() }
                .keyboardShortcut("t")
            Button("Quick capture…") { appDelegate.showQuickCapture() }
            Button("Weekly summary…") { appDelegate.showWeeklySummaryWindow() }
            Button("Medications…") { appDelegate.showMedicationsWindow() }
                .keyboardShortcut("m")
            Button("Water…") { appDelegate.showWaterWindow() }
            Button("AI usage…") { appDelegate.showAIUsageWindow() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Music…") { appDelegate.showMusic() }
            Button("Command palette…") { appDelegate.showCommandPalette() }
                .keyboardShortcut("k", modifiers: [.control, .option])
            Button("Quick notes…") { appDelegate.showTools(.notes) }
            Button("Clipboard…") { appDelegate.showTools(.clipboard) }
            Button("File shelf…") { appDelegate.showTools(.files) }
            Button("Audio mixer…") { appDelegate.showTools(.audio) }
            Button(focusMenu.isFocusing ? "Stop focus" : "Start focus") {
                appDelegate.focus.toggleStartStop()
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])
            Divider()
            Button("Settings…") { appDelegate.showSettingsWindow() }
                .keyboardShortcut(",")
            Button("Getting started…") { appDelegate.showWelcomeWindow() }
            if UpdateChecker.isEnabled {
                Button(updateChecker.state.isChecking ? "Checking…" : "Check for Updates…") {
                    appDelegate.showSettingsWindow(.about)
                    updateChecker.checkForUpdates()
                }.disabled(!updateChecker.state.canCheck)
            }
            Button("Version \(updateChecker.currentVersion)") {}
                .disabled(true)
            Divider()
            Button("Quit NotchFlow") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            // Bare hourglass (no enclosing circle), sized up a touch so it
            // matches the visual weight of the neighbouring menu-bar icons.
            Image(systemName: "hourglass")
                .font(.system(size: 16, weight: .regular))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The running delegate. `NSApp.delegate` is SwiftUI's adaptor, not this
    /// class, so views that need to open a window reach it through here.
    private(set) static weak var shared: AppDelegate?

    static let sharedStore: Store = {
        #if DEBUG
        if Snapshots.isRequested {
            return Store(fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("snapshot-bootstrap-\(UUID()).json"))
        }
        #endif
        return Store()
    }()
    let store = sharedStore
    lazy var focus = FocusTimer(store: store)
    private var notchController: NotchWindowController?
    private var tasksController: TasksWindowController?
    private var waterController: WaterWindowController?
    private var aiUsageController: AIUsageWindowController?
    private var medicationsController: MedicationsWindowController?
    private var settingsController: SettingsWindowController?
    private var summaryController: WeeklySummaryWindowController?
    private var quickCaptureController: QuickCaptureWindowController?
    private var welcomeController: WelcomeWindowController?
    private var viewModel: NotchViewModel?
    func showMusic() { viewModel?.openMusic() }
    private var toolsController: ToolsWindowController?
    private let commandController = CommandPaletteController()
    private let paletteHotkey = GlobalHotkey(id: 3)
    private var paletteHotkeyCancellable: AnyCancellable?

    func showTools(_ section: ToolsSection) {
        guard let model = viewModel?.tools else { return }
        model.section = section
        if toolsController == nil { toolsController = ToolsWindowController(store: store, model: model) }
        toolsController?.show()
    }

    func showCommandPalette() {
        commandController.show(store: store) { [weak self] command in
            guard let self else { return }
            if let id = command.taskID, let task = self.store.tasks.first(where: { $0.id == id && !$0.isDone }) {
                self.focus.start(task: task)
                return
            }
            guard let action = command.action else { return }
            switch action {
            case .capture: self.showQuickCapture()
            case .focus: self.focus.toggleStartStop()
            case .water: self.store.recordWater()
            case .tasks: self.showTasksWindow()
            case .notes: self.showTools(.notes)
            case .clipboard: self.showTools(.clipboard)
            case .files: self.showTools(.files)
            case .audio: self.showTools(.audio)
            case .music: self.showMusic()
            case .ai: self.showAIUsageWindow()
            case .settings: self.showSettingsWindow()
            case .musicToggle, .musicNext, .musicPrevious:
                if let music = self.viewModel?.music, music.playback != nil {
                    music.perform(action == .musicToggle ? .toggle : action == .musicNext ? .next : .previous)
                } else { self.showMusic() }
            }
        }
    }
    private let hotkey = GlobalHotkey()
    private let quickCaptureHotkey = GlobalHotkey(id: 2)
    private var focusCancellable: AnyCancellable?
    /// Mirrors `store.settings.displayPreference` into the view model so the
    /// notch window controller can react via `viewModel.$displayPreference`.
    private var displayPreferenceCancellable: AnyCancellable?
    private var hotkeyCancellable: AnyCancellable?
    private var quickCaptureHotkeyCancellable: AnyCancellable?
    private var taskReminderCancellable: AnyCancellable?

    /// Number of user-openable windows currently up. Drives the activation
    /// policy: the app stays `.accessory` (menu-bar only) until the user
    /// opens Tasks or Settings, at which point it becomes `.regular` so the
    /// window gets a Dock icon and joins the Alt-Tab list.
    private var userWindowCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        #if DEBUG
        if Snapshots.isRequested { Snapshots.run(); return }
        #endif
        NSApp.setActivationPolicy(.accessory)   // no Dock icon; lives in the notch
        NotificationService.shared.onOpenAIUsage = { [weak self] in self?.showAIUsageWindow() }
        AIUsageMonitor.shared.onAlert = { NotificationService.shared.postAIUsageAlert($0) }
        AIUsageMonitor.shared.start()

        // Completing or deleting a task must stop its running session so the
        // collapsed pill's progress line resets instead of running on.
        store.onTaskDeactivated = { [weak self] id, record in
            self?.focus.stopIfActive(id, record: record)
        }
        store.onTaskUpdated = { [weak self] task in
            self?.focus.taskDidChange(task)
        }

        // If the user has notifications on, request authorization on launch so
        // the system prompt is out of the way before the first focus block.
        if store.settings.notificationsEnabled || !store.medications.isEmpty {
            NotificationService.shared.requestAuthorizationIfNeeded()
        }
        store.rescheduleMedicationReminders()
        NotificationService.shared.onOpenTask = { [weak self] id in
            guard let self, self.store.tasks.contains(where: { $0.id == id }) else { return }
            self.store.pendingOpenTaskID = id
            self.showTasksWindow()
        }
        NotificationService.shared.onStartTask = { [weak self] id in
            guard let self, let task = self.store.tasks.first(where: { $0.id == id && !$0.isDone }) else { return }
            self.focus.start(task: task)
        }
        store.rescheduleTaskReminders()
        taskReminderCancellable = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.store.rescheduleTaskReminders()
                _Concurrency.Task { await AIUsageMonitor.shared.refreshAll() }
            }

        // Mirror focus state into the menu so the menu label can show
        // "Start focus" / "Stop focus" live.
        focusCancellable = focus.$state
            .map { $0 != .idle }
            .removeDuplicates()
            .sink { FocusMenuState.shared.update(isFocusing: $0) }

        // Cmd+Shift+Space: toggle the active focus session from anywhere,
        // unless the user switched it off in Settings.
        hotkeyCancellable = store.$settings
            .map(\.globalHotkeyEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in self?.applyHotkey(enabled) }

        quickCaptureHotkeyCancellable = store.$settings
            .map(\.quickCaptureHotkeyEnabled)
            .removeDuplicates()
            .sink { [weak self] enabled in self?.applyQuickCaptureHotkey(enabled) }

        // Start the signed in-app updater and its background schedule.
        UpdateChecker.shared.start()

        let vm = NotchViewModel(store: store, focus: focus, metrics: .primary)
        // Hydrate from the persisted preference before the controller subscribes
        // to `$displayPreference` so the first `reposition(animated: false)`
        // already uses the correct screen. Without this, the saved value would
        // arrive later via the mirror sink and trigger a redundant dock.
        vm.displayPreference = store.settings.displayPreference
        vm.openTasksWindow = { [weak self] in self?.showTasksWindow() }
        vm.openMedicationsWindow = { [weak self] in self?.showMedicationsWindow() }
        viewModel = vm
        paletteHotkeyCancellable = store.$settings.map(\.commandPaletteHotkeyEnabled).removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    FocusMenuState.shared.commandPaletteHotkeyRegistered = self.paletteHotkey.register(
                        keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey)
                    ) { [weak self] in self?.showCommandPalette() }
                } else {
                    self.paletteHotkey.unregister()
                    FocusMenuState.shared.commandPaletteHotkeyRegistered = false
                }
            }
        displayPreferenceCancellable = store.$settings
            .map(\.displayPreference)
            .removeDuplicates()
            .sink { [weak vm] preference in
                vm?.displayPreference = preference
            }
        notchController = NotchWindowController(viewModel: vm)
        if !UserDefaults.standard.bool(forKey: WelcomeWindowController.dismissedKey) {
            showWelcomeWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Preserve an in-flight block when quitting normally or logging out.
        KeepAwakeController.shared.stop()
        if #available(macOS 14.2, *) { AudioMixerModel.shared.stop() }
        focus.stop(record: true)
    }

    func showTasksWindow() { showWorkspace(.tasks) }
    func showWeeklySummaryWindow() { showWorkspace(.summary) }
    func showWaterWindow() { showWorkspace(.water) }
    func showAIUsageWindow() { showWorkspace(.ai) }
    func showMedicationsWindow() { showWorkspace(.medications) }

    func showWorkspace(_ destination: WorkspaceDestination) {
        if tasksController == nil {
            let c = TasksWindowController(store: store, focus: focus)
            // Drop the controller on close so the next open counts as a new
            // window again; keeping it left the count at zero and the reopened
            // window without a Dock icon or a place in ⌘Tab.
            c.onClose = { [weak self] in
                self?.tasksController = nil
                self?.userWindowDidClose()
            }
            tasksController = c
            bumpUserWindowCount()
        }
        tasksController?.show(destination)
    }

    func showQuickCapture() {
        if quickCaptureController == nil { quickCaptureController = QuickCaptureWindowController(store: store) }
        quickCaptureController?.show()
    }

    func showWelcomeWindow() {
        if welcomeController == nil {
            let controller = WelcomeWindowController()
            controller.onClose = { [weak self] in
                self?.welcomeController = nil
                self?.userWindowDidClose()
            }
            controller.onCreateTask = { [weak self] in
                self?.showTasksWindow()
                self?.showQuickCapture()
            }
            controller.onShortcuts = { [weak self] in self?.showSettingsWindow(.shortcuts) }
            welcomeController = controller
            bumpUserWindowCount()
        }
        welcomeController?.show()
    }

    private func showStandaloneSummaryWindow() {
        if summaryController == nil {
            let controller = WeeklySummaryWindowController(store: store, focus: focus)
            controller.onClose = { [weak self] in
                self?.summaryController = nil
                self?.userWindowDidClose()
            }
            summaryController = controller
            bumpUserWindowCount()
        }
        summaryController?.show()
    }

    private func showStandaloneWaterWindow() {
        if waterController == nil {
            let controller = WaterWindowController(store: store, focus: focus)
            controller.onClose = { [weak self] in
                self?.waterController = nil
                self?.userWindowDidClose()
            }
            waterController = controller
            bumpUserWindowCount()
        }
        waterController?.show()
    }

    private func showStandaloneAIWindow() {
        if aiUsageController == nil {
            let controller = AIUsageWindowController(focus: focus)
            controller.onClose = { [weak self] in
                self?.aiUsageController = nil
                self?.userWindowDidClose()
            }
            aiUsageController = controller
            bumpUserWindowCount()
        }
        aiUsageController?.show()
    }

    private func showStandaloneMedicationsWindow() {
        if medicationsController == nil {
            let controller = MedicationsWindowController(store: store, focus: focus)
            controller.onClose = { [weak self] in
                self?.medicationsController = nil
                self?.userWindowDidClose()
            }
            medicationsController = controller
            bumpUserWindowCount()
        }
        medicationsController?.show()
    }

    func showStandaloneWindow(_ destination: WorkspaceDestination) {
        switch destination {
        case .tasks: showTasksWindow()
        case .summary: showStandaloneSummaryWindow()
        case .water: showStandaloneWaterWindow()
        case .ai: showStandaloneAIWindow()
        case .medications: showStandaloneMedicationsWindow()
        }
    }

    func showSettingsWindow(_ page: SettingsPageID? = nil) {
        if settingsController == nil {
            let c = SettingsWindowController(store: store)
            c.onClose = { [weak self] in
                self?.settingsController = nil
                self?.userWindowDidClose()
            }
            settingsController = c
            bumpUserWindowCount()
        }
        settingsController?.show(page)
    }

    private func applyHotkey(_ enabled: Bool) {
        if enabled {
            let ok = hotkey.register(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(cmdKey | shiftKey)
            ) { [weak self] in
                self?.focus.toggleStartStop()
            }
            FocusMenuState.shared.hotkeyRegistered = ok
        } else {
            hotkey.unregister()
            FocusMenuState.shared.hotkeyRegistered = false
        }
    }

    private func applyQuickCaptureHotkey(_ enabled: Bool) {
        if enabled {
            FocusMenuState.shared.quickCaptureHotkeyRegistered = quickCaptureHotkey.register(
                keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey)
            ) { [weak self] in self?.showQuickCapture() }
        } else {
            quickCaptureHotkey.unregister()
            FocusMenuState.shared.quickCaptureHotkeyRegistered = false
        }
    }

    private func bumpUserWindowCount() {
        userWindowCount += 1
        if userWindowCount == 1 {
            // First user window — promote to a regular app so the Dock icon
            // appears and the window joins the Alt-Tab cycle.
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func userWindowDidClose() {
        userWindowCount = max(0, userWindowCount - 1)
        if userWindowCount == 0 {
            // All user windows closed — revert to menu-bar-only mode.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
