import Cocoa
import SwiftUI

private final class KeyableWelcomePanel: NSPanel {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

final class WelcomeWindowController: NSWindowController {
    private static let windowSize = NSSize(width: 760, height: 520)

    convenience init(onContinue: @escaping () -> Void, onClose: @escaping () -> Void) {
        let panel = KeyableWelcomePanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        self.init(window: panel)

        panel.contentView = NSHostingView(rootView: WelcomeView(onContinue: onContinue, onClose: onClose))

        recenterOnActiveScreen()
    }

    private func recenterOnActiveScreen() {
        guard let panel = window else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.origin.x + (frame.width - Self.windowSize.width) / 2
        let y = frame.origin.y + (frame.height - Self.windowSize.height) / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showAndFocus() {
        recenterOnActiveScreen()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
