import AppKit
import SwiftUI

@MainActor
final class AIUsageWindowController: NSObject, NSWindowDelegate {
    private let focus: FocusTimer
    init(focus: FocusTimer) { self.focus = focus }

    private var window: NSWindow?
    var onClose: (() -> Void)?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "AI usage")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 640, height: 550)
            window.contentView = NSHostingView(rootView: AIUsageWindowView().environment(\.flowFocusTimer, focus))
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
