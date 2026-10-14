import AppKit
import SwiftUI

@MainActor
final class WeeklySummaryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: Store
    private let focus: FocusTimer
    var onClose: (() -> Void)?

    init(store: Store, focus: FocusTimer) { self.store = store; self.focus = focus }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "Weekly summary")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WeeklySummaryView()
                .safeAreaInset(edge: .bottom, spacing: 0) { StorePersistenceBanner() }
                .environmentObject(store)
                .environment(\.flowFocusTimer, focus))
            window.contentMinSize = NSSize(width: 620, height: 600)
            window.delegate = self
            window.center()
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
