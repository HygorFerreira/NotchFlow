import AppKit
import SwiftUI

/// A single, optional introduction. Closing it counts as dismissal, and the
/// menu and General settings can always reopen it without resetting preferences.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let dismissedKey = "welcomeDismissed"
    private var window: NSWindow?
    var onClose: (() -> Void)?
    var onCreateTask: (() -> Void)?
    var onShortcuts: (() -> Void)?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 580),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "Getting started")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 600, height: 540)
            window.contentViewController = NSHostingController(rootView: WelcomeView(
                onCreateTask: { [weak self] in
                    guard let self else { return }
                    let action = self.onCreateTask
                    self.window?.close()
                    action?()
                },
                onShortcuts: { [weak self] in
                    guard let self else { return }
                    let action = self.onShortcuts
                    self.window?.close()
                    action?()
                },
                onClose: { [weak self] in self?.window?.close() }))
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
        window = nil
        onClose?()
    }
}

struct WelcomeView: View {
    let onCreateTask: () -> Void
    let onShortcuts: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FlowPageHeading(title: "Welcome to NotchFlow",
                                    subtitle: "A little space for a more focused day", symbol: "hourglass")
                    tip(symbol: "rectangle.topthird.inset.filled", title: "Find your notch",
                        detail: "Move your pointer to the top center of your screen to open the panel. On a Mac without a notch, look for the small pill. The hourglass in the menu bar also opens your tools.")
                    tip(symbol: "checklist", title: "Create a task and focus",
                        detail: "Add your first task, choose its duration, then press play beside it to start a focus block. Your tasks, water, medications and weekly summary share one workspace.")
                    VStack(alignment: .leading, spacing: 12) {
                        tip(symbol: "keyboard", title: "Keep your shortcuts close",
                            detail: "Capture a task from any app with ⌘⇧N. Start or stop focus with ⌘⇧Space. You can check shortcut availability and turn them on or off in Settings.")
                        Button("Review shortcuts…", action: onShortcuts)
                            .buttonStyle(FlowButtonStyle())
                            .padding(.leading, 46)
                    }
                    Text("You can reopen this guide from the menu bar or Settings → General.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Button("Maybe later", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(FlowButtonStyle())
                Spacer()
                Button("Create my first task", action: onCreateTask)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(FlowButtonStyle(prominent: true))
            }
            .padding(20)
        }
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.windowBackground)
        .flowAppearance()
    }

    private func tip(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(symbol: symbol, color: Theme.accent, size: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title.localized)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(detail.localized)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
