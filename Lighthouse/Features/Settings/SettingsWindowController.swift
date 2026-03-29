import Cocoa
import SwiftUI

private final class KeyableSettingsPanel: NSPanel {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

final class SettingsWindowController: NSWindowController {
    private static let defaultSize = NSSize(width: 760, height: 520)

    convenience init() {
        let panel = KeyableSettingsPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
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

        panel.contentView = NSHostingView(rootView: SettingsView(onClose: { [weak panel] in
            panel?.orderOut(nil)
        }))

        recenterOnActiveScreen()
    }

    private func recenterOnActiveScreen() {
        guard let panel = window else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.origin.x + (frame.width - Self.defaultSize.width) / 2
        let y = frame.origin.y + frame.height * 0.58
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
