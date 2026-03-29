import Cocoa
import UserNotifications
import Carbon

private enum AppPrefs {
    static let didCompleteOnboarding = "app.didCompleteOnboarding"
    static let mediaPanelEnabled = "settings.mediaPanelEnabled"
    static let calendarPanelEnabled = "settings.calendarPanelEnabled"
    static let calendarShowMeetButton = "settings.calendarShowMeetButton"
    static let searchThemeColor = "settings.searchThemeColor"
    static let windowBlurEnabled = "settings.windowBlurEnabled"
    static let windowTransparencyEnabled = "settings.windowTransparencyEnabled"
    static let hotKeyMode = "settings.hotKey.mode"
    static let hotKeyCustomModifier = "settings.hotKey.customModifier"
    static let hotKeyCustomKeyCode = "settings.hotKey.customKeyCode"
}

extension Notification.Name {
    static let factoryResetRequested = Notification.Name("lighthouse.factory.reset.requested")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var chatWindow: ChatWindowController?
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?
    private var clickMonitor: Any?
    private let hotKeyManager = HotKeyManager()
    private var defaultsObserver: NSObjectProtocol?

    /// Boots the app in menu-bar mode, wires notifications, and restores hotkey behavior.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        configureHotKeyRegistration()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = statusBarIconImage()
            button.action = #selector(toggleChat)
            button.target = self
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsFromMicroApp),
            name: .openSettingsWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(factoryResetRequested),
            name: .factoryResetRequested,
            object: nil
        )
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureHotKeyRegistration()
        }

        showWelcomeIfNeeded()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .openSettingsWindow, object: nil)
        NotificationCenter.default.removeObserver(self, name: .factoryResetRequested, object: nil)
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    /// Opens or closes the launcher window. If onboarding is not complete, shows onboarding first.
    @objc private func toggleChat() {
        guard isOnboardingComplete else {
            showWelcomeWindow()
            return
        }
        if let win = chatWindow, win.window?.isVisible == true {
            closeChat()
        } else {
            openChat()
        }
    }

    /// Creates and presents the main launcher window, including outside-click dismissal behavior.
    private func openChat() {
        guard isOnboardingComplete else {
            showWelcomeWindow()
            return
        }
        if chatWindow == nil {
            chatWindow = ChatWindowController { [weak self] in self?.closeChat() }
        }
        chatWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        chatWindow?.window?.makeKeyAndOrderFront(nil)
        chatWindow?.window?.makeFirstResponder(chatWindow?.window?.contentView)
        chatWindow?.recenterOnActiveScreen()
        chatWindow?.focusSearch()

        // Close when clicking outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let win = self?.chatWindow?.window else { return }
            if !win.frame.contains(NSEvent.mouseLocation) {
                self?.closeChat()
            }
        }
    }

    /// Hides the launcher window and removes the global click monitor.
    private func closeChat() {
        chatWindow?.window?.orderOut(nil)
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    /// Lazily creates and focuses the settings window.
    @objc private func openSettingsFromMicroApp() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showAndFocus()
    }

    /// Entry point for destructive app reset requested from settings.
    @objc private func factoryResetRequested() {
        performFactoryReset()
    }

    /// Determines whether onboarding has already been completed on this machine.
    private var isOnboardingComplete: Bool {
        UserDefaults.standard.bool(forKey: AppPrefs.didCompleteOnboarding)
    }

    /// Shows onboarding only on first launch / after factory reset.
    private func showWelcomeIfNeeded() {
        guard !isOnboardingComplete else { return }
        showWelcomeWindow()
    }

    /// Presents onboarding and wires completion callbacks.
    private func showWelcomeWindow() {
        if welcomeWindow == nil {
            welcomeWindow = WelcomeWindowController(
                onContinue: { [weak self] in
                    self?.completeOnboarding()
                },
                onClose: { [weak self] in
                    self?.welcomeWindow?.window?.orderOut(nil)
                }
            )
        }
        welcomeWindow?.showAndFocus()
    }

    /// Persists onboarding completion and opens the main launcher.
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppPrefs.didCompleteOnboarding)
        welcomeWindow?.window?.orderOut(nil)
        welcomeWindow = nil
        openChat()
    }

    /// Restores user state to default values and restarts first-run flow.
    private func performFactoryReset() {
        closeChat()
        chatWindow = nil
        settingsWindow?.window?.orderOut(nil)
        welcomeWindow?.window?.orderOut(nil)

        _ = BraveAPIKeyStore.delete()
        HistoryStore.shared.clear()
        UserDefaults.standard.removeObject(forKey: AppPrefs.mediaPanelEnabled)
        UserDefaults.standard.removeObject(forKey: AppPrefs.calendarPanelEnabled)
        UserDefaults.standard.removeObject(forKey: AppPrefs.calendarShowMeetButton)
        UserDefaults.standard.removeObject(forKey: AppPrefs.searchThemeColor)
        UserDefaults.standard.removeObject(forKey: AppPrefs.windowBlurEnabled)
        UserDefaults.standard.removeObject(forKey: AppPrefs.windowTransparencyEnabled)
        UserDefaults.standard.removeObject(forKey: AppPrefs.hotKeyMode)
        UserDefaults.standard.removeObject(forKey: AppPrefs.hotKeyCustomModifier)
        UserDefaults.standard.removeObject(forKey: AppPrefs.hotKeyCustomKeyCode)
        UserDefaults.standard.set(false, forKey: AppPrefs.didCompleteOnboarding)

        configureHotKeyRegistration()
        showWelcomeWindow()
    }

    /// Prefers custom status bar icon asset and falls back to a system symbol.
    private func statusBarIconImage() -> NSImage? {
        if let custom = NSImage(named: NSImage.Name("StatusBarIcon")) {
            custom.size = NSSize(width: 18, height: 18)
            custom.isTemplate = false
            return custom
        }
        let fallback = NSImage(systemSymbolName: "light.beacon.max", accessibilityDescription: "Lighthouse")
        fallback?.isTemplate = true
        return fallback
    }

    /// Registers/unregisters global shortcut according to current user preferences.
    private func configureHotKeyRegistration() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: AppPrefs.hotKeyMode) ?? "replace_spotlight"

        let handler = { [weak self] in
            DispatchQueue.main.async { self?.toggleChat() }
        }

        switch mode {
        case "none":
            hotKeyManager.unregister()
        case "custom":
            let modifierRaw = defaults.string(forKey: AppPrefs.hotKeyCustomModifier) ?? "command"
            let keyCodeInt = defaults.object(forKey: AppPrefs.hotKeyCustomKeyCode) as? Int ?? Int(kVK_Space)
            let modifiers = carbonModifier(for: modifierRaw)
            hotKeyManager.register(
                keyCode: UInt32(keyCodeInt),
                modifiers: modifiers,
                handler: handler
            )
        default:
            hotKeyManager.register(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), handler: handler)
        }
    }

    /// Converts persisted modifier selection into Carbon hotkey modifier flags.
    private func carbonModifier(for raw: String) -> UInt32 {
        switch raw {
        case "option":
            return UInt32(optionKey)
        case "control":
            return UInt32(controlKey)
        case "shift":
            return UInt32(shiftKey)
        default:
            return UInt32(cmdKey)
        }
    }

    /// Allows timer notifications to surface while app runs as accessory app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
