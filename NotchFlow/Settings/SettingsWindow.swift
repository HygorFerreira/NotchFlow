import AppKit
import SwiftUI

/// Pages of the settings window.
enum SettingsPageID: String, CaseIterable, Identifiable {
    case focus, notch, display, alerts, calendar, medications, general, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .notch: return "Notch"
        case .display: return "Display"
        case .alerts: return "Alerts"
        case .calendar: return "Calendar"
        case .medications: return "Medications"
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "hourglass"
        case .notch: return "rectangle.topthird.inset.filled"
        case .display: return "display"
        case .alerts: return "bell.badge.fill"
        case .calendar: return "calendar"
        case .medications: return "pills.fill"
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .focus: return Color(hex: "#F97316")
        case .notch: return Color(hex: "#8B5CF6")
        case .display: return Color(hex: "#0EA5E9")
        case .alerts: return Color(hex: "#EF4444")
        case .calendar: return Color(hex: "#E0457B")
        case .medications: return Color(hex: "#14B8A6")
        case .general: return Color(hex: "#6B7280")
        case .shortcuts: return Color(hex: "#6366F1")
        case .about: return Color(hex: "#475569")
        }
    }

    /// The row and group titles on this page the sidebar search can find. They must match the titles on the page so
    /// a result can scroll to its row.
    var searchableSettings: [String] {
        switch self {
        case .focus: return ["Focus length", "Today's progress"]
        case .notch: return ["Appearance", "Standard", "Minimal", "Liquid Glass", "Transparency", "Progress timeline", "RGB timeline"]
        case .display: return ["Show the notch on", "Connected displays"]
        case .alerts: return ["Notification", "Sound", "Notifications are off"]
        case .calendar: return ["Calendar access"]
        case .medications: return ["Add medication", "Daily reminders", "Reminder times"]
        case .general: return ["Open at login", "Language", "Your data", "Restore defaults"]
        case .shortcuts: return ["Start or stop focus", "Quick capture", "From any app", "Tasks window", "Menu bar"]
        case .about: return ["Updates", "Privacy"]
        }
    }

    static let sections: [[SettingsPageID]] = [
        [.focus, .notch, .display, .alerts, .calendar, .medications],
        [.general, .shortcuts, .about],
    ]
}

/// A search hit: a page, or one setting on it.
struct SettingsSearchEntry: Identifiable {
    let title: String
    let page: SettingsPageID
    var isPage: Bool { title == page.title }
    var id: String { "\(page.rawValue):\(title)" }

    static func results(for query: String) -> [SettingsSearchEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return SettingsPageID.allCases.flatMap { page in
            ([page.title] + page.searchableSettings)
                // Matches what is on screen, and the English name too.
                .filter { $0.localized.localizedCaseInsensitiveContains(needle) || $0.localizedCaseInsensitiveContains(needle) }
                .map { SettingsSearchEntry(title: $0, page: page) }
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsPageID = .focus
    /// The setting a search result pointed at: its page scrolls to it and lights it up for a moment, then this goes
    /// back to nil.
    var highlightedSetting: String?

    func open(_ entry: SettingsSearchEntry) {
        page = entry.page
        highlightedSetting = entry.isPage ? nil : entry.title
    }
}

/// Owns the single settings window, so the menu bar, the Tasks window and the notch all open the same one.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: Store
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    /// Fires when the window closes. The app delegate uses it to drop back to a menu-bar-only app when the last
    /// user window goes away.
    var onClose: (() -> Void)?

    init(store: Store) {
        self.store = store
        super.init()
    }

    var isOpen: Bool { window != nil }

    func show(_ page: SettingsPageID? = nil) {
        if let page { navigation.page = page }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = String(localized: "NotchFlow Settings")
            // A full-size content view so the sidebar runs up to the top of the window with the traffic lights sitting
            // on it, the way System Settings has it.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 720, height: 480)
            window.contentViewController = NSHostingController(
                rootView: SettingsWindowView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { StorePersistenceBanner() }
                    .environmentObject(store)
                    .environment(navigation))
            window.setContentSize(NSSize(width: 820, height: 600))
            window.center()
            window.setFrameAutosaveName("NotchFlowSettings")
            window.delegate = self
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
    }
}

/// The sidebar on the left, running the full height of the window, and the selected page on the right.
struct SettingsWindowView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        NavigationSplitView {
            SettingsSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Group {
                switch navigation.page {
                case .focus: FocusSettingsPage()
                case .notch: NotchSettingsPage()
                case .display: DisplaySettingsPage()
                case .alerts: AlertsSettingsPage()
                case .calendar: CalendarSettingsPage()
                case .medications: MedicationsSettingsPage()
                case .general: GeneralSettingsPage()
                case .shortcuts: ShortcutsSettingsPage()
                case .about: AboutSettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.top, 32)
            .clipped()
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.windowBackground)
        .flowAppearance()
    }
}

/// System Settings' sidebar: search on top, the pages under it, the window's wallpaper showing faintly through.
private struct SettingsSidebar: View {
    @Environment(SettingsNavigation.self) private var navigation
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<SettingsPageID?>(
                get: { navigation.page },
                set: { if let page = $0 { navigation.page = page } })) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(Array(SettingsPageID.sections.enumerated()), id: \.offset) { index, section in
                        Section(index == 0 ? String(localized: "DAILY ROUTINE") : String(localized: "APPLICATION")) {
                            ForEach(section) { page in
                                Label {
                                    Text(page.title.localized)
                                        .foregroundStyle(navigation.page == page ? Color.white : Color.primary)
                                } icon: {
                                    SettingsIcon(symbol: page.symbol, color: page.color, size: 24)
                                }
                                .padding(.vertical, 3)
                                .tag(page)
                            }
                        }
                    }
                } else {
                    results
                }
            }
            .listStyle(.sidebar)
            .tint(Theme.accent)
            .searchable(text: $query, placement: .sidebar)
            footer
        }
        .navigationTitle("NotchFlow")
    }

    @ViewBuilder
    private var results: some View {
        let found = SettingsSearchEntry.results(for: query)
        if found.isEmpty {
            Text("No Results")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
        // Grouped under the page they are on, in the sidebar's own order.
        ForEach(SettingsPageID.allCases) { page in
            let onPage = found.filter { $0.page == page }
            if !onPage.isEmpty {
                SidebarRow(page: page, isSelected: false) {
                    navigation.open(SettingsSearchEntry(title: page.title, page: page))
                }
                ForEach(onPage.filter { !$0.isPage }) { entry in
                    Button {
                        navigation.open(entry)
                    } label: {
                        Text(entry.title.localized)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 42)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer().frame(height: 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(SettingsPalette.selection)
            Text("Your tasks never leave your Mac.")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One page in the sidebar: colored icon and name, filled with the accent color while it is the one open.
private struct SidebarRow: View {
    let page: SettingsPageID
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: page.symbol, color: page.color, size: 24)
                Text(page.title.localized)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
