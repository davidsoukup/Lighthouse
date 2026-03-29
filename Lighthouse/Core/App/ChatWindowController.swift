import Cocoa
import SwiftUI

// Borderless panels can't become key by default — override to allow keyboard input
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

final class ChatWindowController: NSWindowController {

    private static let windowWidth:  CGFloat = 620
    private static let emptyHeight:  CGFloat = 60
    private static let fullHeight:   CGFloat = 560
    private static let topOffsetFraction: CGFloat = 0.22
    private var lastHeight: CGFloat = 60   // matches initial panel height

    /// Computes launcher origin so the window appears slightly higher than center.
    private static func originOnScreen(visibleFrame: NSRect, windowHeight: CGFloat) -> NSPoint {
        let x = visibleFrame.origin.x + (visibleFrame.width - Self.windowWidth) / 2
        let targetTopY = visibleFrame.maxY - (visibleFrame.height * Self.topOffsetFraction)
        let y = max(visibleFrame.minY, targetTopY - windowHeight)
        return NSPoint(x: x, y: y)
    }

    /// Builds borderless launcher panel and injects SwiftUI root view.
    convenience init(onClose: @escaping () -> Void) {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.emptyHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel    = true
        panel.level              = .floating
        panel.backgroundColor    = .clear
        panel.isOpaque           = false
        panel.hasShadow          = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.init(window: panel)

        let view = LauncherView(
            onClose: onClose,
            onHeightChange: { [weak self] h in self?.updateHeight(h) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.masksToBounds = true
        if #available(macOS 11.0, *) {
            hosting.layer?.cornerCurve = .continuous
        }
        panel.contentView = hosting

        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(Self.originOnScreen(visibleFrame: frame, windowHeight: Self.emptyHeight))
        }
    }

    /// Repositions panel for the active screen (multi-display aware).
    func recenterOnActiveScreen() {
        guard let panel = window else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(Self.originOnScreen(visibleFrame: frame, windowHeight: panel.frame.height))
    }

    /// Asks launcher view to focus the search field.
    func focusSearch() {
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }

    /// Resizes panel while keeping top edge visually anchored.
    private func updateHeight(_ height: CGFloat) {
        guard let panel = window, abs(height - lastHeight) > 1 else { return }
        let oldHeight = panel.frame.height
        let oldOrigin = panel.frame.origin
        lastHeight = height
        let newOrigin = NSPoint(
            x: oldOrigin.x,
            y: oldOrigin.y + oldHeight - height
        )
        panel.setFrame(
            NSRect(origin: newOrigin, size: NSSize(width: Self.windowWidth, height: height)),
            display: false
        )
    }

    override func close() {
        window?.orderOut(nil)
    }
}
