#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: renders every window of the app into PNGs with demo data, for the README and the App Store
/// screenshots, then quits. Nothing is read from or written to the user's real data file.
///
///     NotchFlow.app/Contents/MacOS/NotchFlow -snapshot 1 [-AppleLanguages '(pt-BR)']
///
/// The PNGs land in the app's temporary folder (the sandbox allows nothing else); the path is printed.
@MainActor
enum Snapshots {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "snapshot") || UserDefaults.standard.bool(forKey: "preview")
    }
    private static var previewWindows: [NSWindow] = []

    static func run() {
        if UserDefaults.standard.bool(forKey: "preview") {
            if UserDefaults.standard.bool(forKey: "previewTools") { showToolsPreview(); return }
            showPreview()
            return
        }
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let store = demoStore()
        let focus = FocusTimer(store: store)

        if UserDefaults.standard.bool(forKey: "snapshotToolsOnly") {
            let vm = NotchViewModel(store: store, focus: focus, metrics: .primary)
            store.addQuickNote(isPortuguese ? "Ideias para a próxima versão\nRevisar o fluxo de foco e organizar as tarefas da semana." : "Ideas for the next release\nReview the focus flow and organize this week's tasks.")
            store.addQuickNote(isPortuguese ? "Preparar a reunião\nSeparar as decisões e os próximos passos." : "Prepare the meeting\nGather decisions and next steps.")
            vm.tools.clipboard.setDemo()
            let file = out.appendingPathComponent("Project brief.txt")
            try? Data("Demo file for visual review".utf8).write(to: file)
            vm.tools.shelf.importFiles([file])
            for section in ToolsSection.allCases {
                vm.tools.section = section
                render(ToolsView(model: vm.tools).padding(20).background(Theme.windowBackground).flowAppearance().environmentObject(store),
                    size: CGSize(width: 760, height: 460), scheme: .dark, to: out.appendingPathComponent("tools-\(section.id.replacingOccurrences(of: " ", with: "-").lowercased()).png"))
                render(ToolsView(model: vm.tools).padding(20).background(Theme.windowBackground).flowAppearance().environmentObject(store),
                    size: CGSize(width: 640, height: 400), scheme: .light, to: out.appendingPathComponent("tools-\(section.id.replacingOccurrences(of: " ", with: "-").lowercased())-light.png"))
                vm.openTools(section)
                render(notch(vm), size: vm.targetSize, scheme: .dark,
                    to: out.appendingPathComponent("notch-tools-\(section.id.replacingOccurrences(of: " ", with: "-").lowercased()).png"))
            }
            render(CommandPaletteView(onRun: { _ in }, onClose: {}).environmentObject(store),
                size: CGSize(width: 560, height: 420), scheme: .dark, to: out.appendingPathComponent("command-palette.png"))
            vm.debugSetUpcomingEvent(UpcomingEvent(title: isPortuguese ? "Reunião de produto" : "Product meeting",
                start: Date().addingTimeInterval(300), end: Date().addingTimeInterval(2100), meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")))
            if let task = store.tasks.first { focus.start(task: task) }
            vm.expanded = false
            render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("upcoming-event.png"))
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        if UserDefaults.standard.bool(forKey: "snapshotMusicOnly") {
            let vm = NotchViewModel(store: store, focus: focus, metrics: .primary)
            let track = MusicPlayback(id: "demo", title: "A Walk Through the City", artist: "NotchFlow Sessions",
                duration: 245, position: 84, isPlaying: true, sampledAt: Date())
            vm.music.setDemo(track)
            vm.music.lyrics.setDemo()
            vm.openMusic()
            render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("music-player.png"))
            vm.expanded = false
            render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("music-compact.png"))
            vm.musicPeek = true
            render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("music-peek.png"))
            if let task = store.tasks.first {
                focus.start(task: task)
                focus.debugAdvance(seconds: 90)
                vm.musicPeek = false
                render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("music-focus.png"))
                vm.musicPeek = true
                vm.debugShowReminder(.water)
                render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("music-focus-reminder.png"))
                vm.dismissReminder()
            }
            vm.music.setDemo(nil)
            vm.musicPeek = false
            vm.openMusic()
            render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("music-empty.png"))
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        if UserDefaults.standard.bool(forKey: "snapshotRoutineOnly") {
            let vm = NotchViewModel(store: store, focus: focus, metrics: .primary)
            vm.debugSetUpcomingEvent(UpcomingEvent(title: isPortuguese ? "Reunião de produto" : "Product meeting",
                start: Date().addingTimeInterval(480), end: Date().addingTimeInterval(2280),
                meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")))
            vm.expanded = true
            for tab in ["Activity", "Health", "Machine"] {
                vm.dashboardTab = tab
                render(notch(vm), size: vm.targetSize, scheme: .dark,
                       to: out.appendingPathComponent("routine-\(tab.lowercased()).png"))
            }
            vm.expanded = false
            vm.debugShowReminder(.routineBreak(.eyes))
            render(notch(vm), size: vm.targetSize, scheme: .dark,
                   to: out.appendingPathComponent("routine-reminder.png"))
            render(AIUsageDashboardView(monitor: .demo()).padding(20).background(Color.black),
                   size: CGSize(width: 700, height: 210), scheme: .dark,
                   to: out.appendingPathComponent("routine-ai.png"))
            for scheme in [ColorScheme.dark, .light] {
                render(DashboardModuleSettings().environmentObject(store).padding(24).background(Theme.windowBackground).flowAppearance(), size: CGSize(width: 720, height: 430), scheme: scheme,
                       to: out.appendingPathComponent("routine-modules-\(scheme == .dark ? "dark" : "light").png"))
                render(RoutineBreakSettings().environmentObject(store).padding(24).background(Theme.windowBackground).flowAppearance(), size: CGSize(width: 720, height: 480), scheme: scheme,
                       to: out.appendingPathComponent("routine-breaks-\(scheme == .dark ? "dark" : "light").png"))
            }
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        if UserDefaults.standard.bool(forKey: "snapshotWelcomeOnly") {
            for scheme in [ColorScheme.dark, .light] {
                render(WelcomeView(onCreateTask: {}, onShortcuts: {}, onClose: {}),
                       size: CGSize(width: 600, height: 580), scheme: scheme,
                       to: out.appendingPathComponent("welcome-\(scheme == .dark ? "dark" : "light").png"))
            }
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        if UserDefaults.standard.bool(forKey: "snapshotNotchOnly") {
            store.medications.append(Medication(name: "Vitamina D", dosage: "1000 UI",
                                                reminderTimes: [Date().addingTimeInterval(3600)]))
            renderNotchReview(store: store, focus: focus, to: out)
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        if UserDefaults.standard.bool(forKey: "snapshotVisualReview") {
            renderVisualReview(store: store, focus: focus, to: out)
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        let aiMonitor = AIUsageMonitor.demo()
        for scheme in [ColorScheme.dark, .light] {
            render(AIUsageWindowView(monitor: aiMonitor), size: CGSize(width: 700, height: 740), scheme: scheme,
                   to: out.appendingPathComponent("ai-usage-\(scheme == .dark ? "dark" : "light").png"))
        }
        render(AIUsageDashboardView(monitor: aiMonitor).padding(18).background(.black),
               size: CGSize(width: 560, height: 190), scheme: .dark,
               to: out.appendingPathComponent("ai-dashboard.png"))
        let emptyMonitor = AIUsageMonitor(defaults: UserDefaults(suiteName: "notchflow-ai-empty-\(UUID())")!)
        render(AIUsageWindowView(monitor: emptyMonitor), size: CGSize(width: 640, height: 550), scheme: .light,
               to: out.appendingPathComponent("ai-empty.png"))
        render(AIUsageWindowView(monitor: AIUsageMonitor.demo(stale: true)),
               size: CGSize(width: 640, height: 740), scheme: .dark,
               to: out.appendingPathComponent("ai-stale.png"))
        if UserDefaults.standard.bool(forKey: "snapshotAIOnly") {
            print("SNAPSHOTS \(out.path)")
            exit(0)
        }

        for scheme in [ColorScheme.dark, .light] {
            for page in SettingsPageID.allCases {
                let navigation = SettingsNavigation()
                navigation.page = page
                let view = SettingsWindowView()
                    .environmentObject(store)
                    .environment(navigation)
                    .background(Color(nsColor: .windowBackgroundColor))
                render(view, size: CGSize(width: 820, height: 820), scheme: scheme,
                       to: out.appendingPathComponent("settings-\(page.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }

        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            render(TasksWindowView().environmentObject(store).environmentObject(focus),
                   size: CGSize(width: 900, height: 680), scheme: scheme,
                   to: out.appendingPathComponent("tasks-\(suffix).png"))
            render(WeeklySummaryView().environmentObject(store),
                   size: CGSize(width: 700, height: 1000), scheme: scheme,
                   to: out.appendingPathComponent("summary-\(suffix).png"))
        }

        render(TasksWindowView().environmentObject(store).environmentObject(focus),
               size: CGSize(width: 900, height: 640), scheme: .dark,
               to: out.appendingPathComponent("tasks.png"))

        // Demo rendering must never schedule real system notifications.
        store.medications.append(Medication(name: isPortuguese ? "Vitamina D" : "Vitamin D",
                                            dosage: "1000 UI", reminderTimes: [Date().addingTimeInterval(3600)]))
        var waterSettings = HydrationSettings()
        waterSettings.container = .bottle
        waterSettings.bottleMilliliters = 750
        store.updateHydrationSettings(waterSettings)
        store.recordWater()
        render(WaterWindowView().environmentObject(store),
               size: CGSize(width: 680, height: 920), scheme: .dark,
               to: out.appendingPathComponent("water.png"))
        render(WaterDashboardView().environmentObject(store).padding(18).background(Color.black),
               size: CGSize(width: 580, height: 214), scheme: .dark,
               to: out.appendingPathComponent("water-dashboard.png"))
        render(MedicationFormView(onSave: { _, _, _ in }),
               size: CGSize(width: 500, height: 520), scheme: .dark,
               to: out.appendingPathComponent("medication-form.png"))
        render(MedicationsView().environmentObject(store),
               size: CGSize(width: 680, height: 520), scheme: .dark,
               to: out.appendingPathComponent("medications.png"))
        render(MachineDashboardView().padding(18).background(Color.black),
               size: CGSize(width: 560, height: 214), scheme: .dark,
               to: out.appendingPathComponent("machine.png"))

        render(WeeklySummaryView().environmentObject(store),
               size: CGSize(width: 700, height: 880), scheme: .dark,
               to: out.appendingPathComponent("weekly-summary.png"))
        render(QuickCaptureView(onClose: {}).environmentObject(store),
               size: CGSize(width: 460, height: 420), scheme: .dark,
               to: out.appendingPathComponent("quick-capture.png"))
        if let first = store.tasks.first {
            var task = first
            task.project = isPortuguese ? "Trabalho" : "Work"
            task.tags = ["swift", "review"]
            task.recurrence = TaskRecurrence(frequency: .custom, weekdays: [2, 4, 6])
            task.startTime = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date())
            task.reminderMinutesBefore = 10
            render(TaskDetailView(task: task).environmentObject(store).environmentObject(focus),
                   size: CGSize(width: 480, height: 700), scheme: .dark,
                   to: out.appendingPathComponent("task-organization.png"))
        }

        let metrics = NotchMetrics.primary
        let vm = NotchViewModel(store: store, focus: focus, metrics: metrics)
        vm.debugShowReminder(.medication(Medication(name: "Vitamina D", dosage: "1 cápsula", reminderTimes: [])))
        render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("notch-medication-reminder.png"))
        vm.debugShowReminder(.water)
        render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("notch-water-reminder.png"))
        vm.dismissReminder()
        vm.expanded = true
        render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("notch-expanded.png"))

        if let first = store.tasks(on: Date()).first {
            focus.start(task: first)
            // Mid-block, so the countdown and the progress line both show.
            focus.debugAdvance(seconds: Double(first.estimateMinutes * 60) * 0.38)
        }
        for scheme in [ColorScheme.dark, .light] {
            render(TasksWindowView().environmentObject(store).environmentObject(focus),
                   size: CGSize(width: 900, height: 680), scheme: scheme,
                   to: out.appendingPathComponent("tasks-focus-\(scheme == .dark ? "dark" : "light").png"))
        }
        focus.pause()
        render(TasksWindowView().environmentObject(store).environmentObject(focus),
               size: CGSize(width: 900, height: 680), scheme: .light,
               to: out.appendingPathComponent("tasks-paused.png"))
        focus.togglePause()
        vm.expanded = false
        render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("notch-focus.png"))
        store.settings.rainbowTimeline = true
        render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("notch-focus-rgb.png"))
        store.settings.rainbowTimeline = false
        store.settings.minimalMode = true
        render(notch(vm), size: vm.targetSize, scheme: .dark, to: out.appendingPathComponent("notch-focus-minimal.png"))

        print("SNAPSHOTS \(out.path)")
        exit(0)
    }

    /// Live, isolated preview: native glass is composited by WindowServer and
    /// cannot always be captured accurately through NSView.cacheDisplay.
    private static func showPreview() {
        let store = demoStore()
        let focus = FocusTimer(store: store)
        NSApp.setActivationPolicy(.regular)
        let tasks = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        tasks.title = "NotchFlow · Preview"
        tasks.isReleasedWhenClosed = false
        tasks.contentViewController = NSHostingController(rootView:
            TasksWindowView().environmentObject(store).environmentObject(focus))
        tasks.setContentSize(NSSize(width: 960, height: 720))
        tasks.center()
        let navigation = SettingsNavigation()
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 650),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: false)
        settings.title = "Settings · Preview"
        settings.isReleasedWhenClosed = false
        settings.contentViewController = NSHostingController(rootView:
            SettingsWindowView().environmentObject(store).environment(navigation))
        settings.setContentSize(NSSize(width: 820, height: 650))
        settings.center()
        // Additional overview windows share the demo timer for cross-window UX checks.
        store.medications.append(Medication(name: "Vitamina D", dosage: "1000 UI", reminderTimes: [Date()]))
        let water = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        water.title = "Water · Preview"
        water.isReleasedWhenClosed = false
        water.contentViewController = NSHostingController(rootView:
            WaterWindowView().environmentObject(store).environment(\.flowFocusTimer, focus))
        water.setContentSize(NSSize(width: 680, height: 740))
        water.center()
        let medications = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
        medications.title = "Medications · Preview"
        medications.isReleasedWhenClosed = false
        medications.contentViewController = NSHostingController(rootView:
            MedicationsView().environmentObject(store).environment(\.flowFocusTimer, focus))
        medications.setContentSize(NSSize(width: 740, height: 600))
        medications.center()
        previewWindows = [tasks, settings, water, medications]
        water.orderFront(nil)
        medications.orderFront(nil)
        settings.orderFront(nil)
        tasks.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func showToolsPreview() {
        let store = demoStore()
        store.addQuickNote("Preview note\nThis is isolated demo data.")
        let model = ToolsModel(isolated: true)
        model.clipboard.setDemo()
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Tools · Preview"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ToolsView(model: model).padding(20).background(Theme.windowBackground).flowAppearance().environmentObject(store))
        window.center()
        previewWindows = [window]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A focused, repeatable review of the shared design in both appearances.
    private static func renderVisualReview(store: Store, focus: FocusTimer, to out: URL) {
        store.medications.append(Medication(name: isPortuguese ? "Vitamina D" : "Vitamin D",
                                            dosage: "1000 UI", reminderTimes: [Date().addingTimeInterval(3600)]))
        store.recordWater()
        let monitor = AIUsageMonitor.demo()
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            render(TasksWindowView().environmentObject(store).environmentObject(focus),
                   size: CGSize(width: 1020, height: 740), scheme: scheme,
                   to: out.appendingPathComponent("tasks-\(suffix).png"))
            render(WaterWindowView().environmentObject(store),
                   size: CGSize(width: 720, height: 940), scheme: scheme,
                   to: out.appendingPathComponent("water-\(suffix).png"))
            render(MedicationsView().environmentObject(store),
                   size: CGSize(width: 740, height: 560), scheme: scheme,
                   to: out.appendingPathComponent("medications-\(suffix).png"))
            render(WeeklySummaryView().environmentObject(store),
                   size: CGSize(width: 740, height: 1050), scheme: scheme,
                   to: out.appendingPathComponent("summary-\(suffix).png"))
            render(AIUsageWindowView(monitor: monitor),
                   size: CGSize(width: 740, height: 940), scheme: scheme,
                   to: out.appendingPathComponent("ai-\(suffix).png"))
            for page in SettingsPageID.allCases {
                let navigation = SettingsNavigation()
                navigation.page = page
                render(SettingsWindowView().environmentObject(store).environment(navigation),
                       size: CGSize(width: 820, height: 820), scheme: scheme,
                       to: out.appendingPathComponent("settings-\(page.rawValue)-\(suffix).png"))
            }
            if let task = store.tasks.first {
                render(TaskDetailView(task: task).environmentObject(store).environmentObject(focus),
                       size: CGSize(width: 500, height: 740), scheme: scheme,
                       to: out.appendingPathComponent("task-detail-\(suffix).png"))
            }
            render(QuickCaptureView(onClose: {}).environmentObject(store),
                   size: CGSize(width: 460, height: 420), scheme: scheme,
                   to: out.appendingPathComponent("quick-capture-\(suffix).png"))
        }
        renderNotchReview(store: store, focus: focus, to: out)
    }

    private static func renderNotchReview(store: Store, focus: FocusTimer, to out: URL) {
        let vm = NotchViewModel(store: store, focus: focus, metrics: .primary)
        vm.expanded = true
        for tab in ["Activity", "Health", "Machine", "Water", "AI"] {
            vm.dashboardTab = tab
            render(notch(vm).background(Color(hex: "#708DB6")), size: vm.targetSize, scheme: .dark,
                   to: out.appendingPathComponent("notch-\(tab.lowercased()).png"))
        }
        if let task = store.tasks.first {
            focus.start(task: task)
            focus.debugAdvance(seconds: Double(task.estimateMinutes * 60) * 0.38)
            vm.expanded = false
            render(notch(vm).background(Color(hex: "#708DB6")), size: vm.targetSize, scheme: .dark,
                   to: out.appendingPathComponent("notch-focus.png"))
        }
    }

    private static func notch(_ vm: NotchViewModel) -> some View {
        RootNotchView()
            .environmentObject(vm)
            .environmentObject(vm.store)
            .environmentObject(vm.focus)
    }

    private static func render<V: View>(_ view: V, size: CGSize, scheme: ColorScheme, to url: URL) {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        // Let SwiftUI lay out and draw.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    // MARK: - Demo data

    private static var isPortuguese: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("pt") == true
    }

    private static func demoStore() -> Store {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapshot-data.json")
        try? FileManager.default.removeItem(at: file)
        let store = Store(fileURL: file, taskReminderScheduler: { _ in })
        store.settings.notificationsEnabled = false
        store.settings.playSound = false

        let pt = isPortuguese
        let today: [(String, String, Int, Bool)] = [
            (pt ? "Escrever o relatório trimestral" : "Write the quarterly report",
             pt ? "Números de receita e próximos passos" : "Revenue numbers and next steps", 45, false),
            (pt ? "Revisar pull requests" : "Review pull requests", "", 25, false),
            (pt ? "Planejar a próxima sprint" : "Plan the next sprint",
             pt ? "Priorizar o backlog com o time" : "Prioritize the backlog with the team", 30, false),
            (pt ? "Responder o feedback de design" : "Reply to design feedback", "", 15, true),
        ]
        for (title, notes, minutes, done) in today {
            store.add(title: title, notes: notes, estimate: minutes, date: Date())
            if done, let task = store.tasks.last { store.toggleDone(task) }
        }
        store.add(title: pt ? "Ler sobre SwiftUI" : "Read up on SwiftUI", estimate: 30, date: nil)

        // A believable month: most weekdays have a few blocks, the last days in a row form a streak.
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        for back in 0..<40 {
            guard let day = cal.date(byAdding: .day, value: -back, to: start) else { continue }
            let blocks = back < 6 ? [3, 4, 2, 5, 3, 4][back] : [0, 1, 2, 0, 3, 1, 4, 2, 0, 2][back % 10]
            for b in 0..<blocks {
                let begin = day.addingTimeInterval(TimeInterval(9 * 3600 + b * 3600))
                store.recordSession(FocusSession(taskId: nil, startedAt: begin,
                                                 endedAt: begin.addingTimeInterval(25 * 60), completed: true))
            }
        }
        return store
    }
}
#endif
