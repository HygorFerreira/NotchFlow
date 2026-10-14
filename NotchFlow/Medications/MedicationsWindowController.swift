import AppKit
import SwiftUI

@MainActor
final class MedicationsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: Store
    private let focus: FocusTimer
    var onClose: (() -> Void)?

    init(store: Store, focus: FocusTimer) {
        self.store = store
        self.focus = focus
    }

    func show() {
        if window == nil {
            let root = MedicationsView()
                .safeAreaInset(edge: .bottom, spacing: 0) { StorePersistenceBanner() }
                .environmentObject(store)
                .environment(\.flowFocusTimer, focus)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = String(localized: "Medications")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .windowBackgroundColor
            window.contentView = NSHostingView(rootView: root)
            window.contentMinSize = NSSize(width: 680, height: 520)
            window.delegate = self
            self.window = window
        }

        centerOnActiveScreen()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func centerOnActiveScreen() {
        guard let window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
        )
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
    }
}
