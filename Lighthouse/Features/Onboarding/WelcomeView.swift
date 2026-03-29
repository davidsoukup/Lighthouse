import SwiftUI
import AppKit
import UserNotifications
import Carbon
import EventKit

struct WelcomeView: View {
    var onContinue: () -> Void
    var onClose: () -> Void = {}

    @State private var currentFeatureIndex: Int = 0
    @State private var step: Step = .intro
    @State private var notificationsGranted: Bool = false
    @State private var notificationsKnown: Bool = false
    @State private var automationStatus: PermissionState = .unknown
    @State private var calendarStatus: PermissionState = .unknown
    @State private var isCapturingCustomKey: Bool = false
    @State private var keyCaptureMonitor: Any? = nil

    @AppStorage("settings.windowBlurEnabled") private var windowBlurEnabled: Bool = true
    @AppStorage("settings.windowTransparencyEnabled") private var windowTransparencyEnabled: Bool = true
    @AppStorage("settings.hotKey.mode") private var hotKeyModeRaw: String = HotKeyMode.replaceSpotlight.rawValue
    @AppStorage("settings.hotKey.customModifier") private var hotKeyCustomModifierRaw: String = HotKeyModifier.command.rawValue
    @AppStorage("settings.hotKey.customKeyCode") private var hotKeyCustomKeyCode: Int = Int(kVK_Space)
    @AppStorage("settings.appLanguage") private var appLanguageRaw: String = AppLanguage.en.rawValue

    private enum Step {
        case intro
        case permissions
        case howItWorks
    }

    private struct WelcomeFeature: Identifiable {
        let id: String
        let title: String
        let description: String
        let symbol: String
    }

    private enum HotKeyMode: String, CaseIterable, Identifiable {
        case replaceSpotlight = "replace_spotlight"
        case custom = "custom"
        case none = "none"

        var id: String { rawValue }
        var title: String {
            switch self {
            case .replaceSpotlight: return lh("hotkey.mode.replace_spotlight")
            case .custom: return lh("hotkey.mode.custom")
            case .none: return lh("hotkey.mode.none")
            }
        }
    }

    private enum HotKeyModifier: String, CaseIterable, Identifiable {
        case command
        case option
        case control
        case shift

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .command: return "\u{2318}"
            case .option: return "\u{2325}"
            case .control: return "\u{2303}"
            case .shift: return "\u{21E7}"
            }
        }
        var title: String {
            switch self {
            case .command: return lh("hotkey.modifier.command")
            case .option: return lh("hotkey.modifier.option")
            case .control: return lh("hotkey.modifier.control")
            case .shift: return lh("hotkey.modifier.shift")
            }
        }
    }

    private struct HotKeyChoice: Identifiable {
        let id: String
        let title: String
        let keyCode: Int
        let symbol: String
    }

    private var features: [WelcomeFeature] {
        [
            .init(
                id: "privacy",
                title: lh("onboarding.feature.privacy.title"),
                description: lh("onboarding.feature.privacy.description"),
                symbol: "lock.shield"
            ),
            .init(id: "apps", title: lh("onboarding.feature.apps.title"), description: lh("onboarding.feature.apps.description"), symbol: "app.badge"),
            .init(id: "files", title: lh("onboarding.feature.files.title"), description: lh("onboarding.feature.files.description"), symbol: "folder"),
            .init(id: "web", title: lh("onboarding.feature.web.title"), description: lh("onboarding.feature.web.description"), symbol: "globe"),
            .init(id: "micro", title: lh("onboarding.feature.micro.title"), description: lh("onboarding.feature.micro.description"), symbol: "terminal"),
            .init(id: "hotkey", title: lh("onboarding.feature.hotkey.title"), description: lh("onboarding.feature.hotkey.description"), symbol: "command"),
            .init(id: "native", title: lh("onboarding.feature.native.title"), description: lh("onboarding.feature.native.description"), symbol: "swift")
        ]
    }

    private let customHotKeyChoices: [HotKeyChoice] = [
        .init(id: "space", title: "Space", keyCode: Int(kVK_Space), symbol: "Space"),
        .init(id: "return", title: "Return", keyCode: Int(kVK_Return), symbol: "Return"),
        .init(id: "a", title: "A", keyCode: Int(kVK_ANSI_A), symbol: "A"),
        .init(id: "s", title: "S", keyCode: Int(kVK_ANSI_S), symbol: "S"),
        .init(id: "d", title: "D", keyCode: Int(kVK_ANSI_D), symbol: "D"),
        .init(id: "f", title: "F", keyCode: Int(kVK_ANSI_F), symbol: "F"),
        .init(id: "g", title: "G", keyCode: Int(kVK_ANSI_G), symbol: "G"),
        .init(id: "h", title: "H", keyCode: Int(kVK_ANSI_H), symbol: "H"),
        .init(id: "j", title: "J", keyCode: Int(kVK_ANSI_J), symbol: "J"),
        .init(id: "k", title: "K", keyCode: Int(kVK_ANSI_K), symbol: "K"),
        .init(id: "l", title: "L", keyCode: Int(kVK_ANSI_L), symbol: "L")
    ]

    /// Main onboarding container that switches between intro, setup, and how-it-works steps.
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)

            if step == .intro {
                introContent
            } else if step == .permissions {
                permissionsContent
            } else {
                howItWorksContent
            }
        }
        .background(welcomeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .frame(width: 760, height: 520)
        .task {
            guard features.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        currentFeatureIndex = (currentFeatureIndex + 1) % features.count
                    }
                }
            }
        }
        .task {
            await refreshNotificationStatus()
        }
        .onDisappear {
            stopHotKeyCapture()
        }
        .environment(\.locale, appLanguage.locale)
    }

    private var hasAtLeastOnePermission: Bool {
        notificationsGranted || automationStatus == .allowed || calendarStatus == .allowed
    }

    private var hotKeyMode: HotKeyMode {
        HotKeyMode(rawValue: hotKeyModeRaw) ?? .replaceSpotlight
    }

    private var hotKeyModifier: HotKeyModifier {
        HotKeyModifier(rawValue: hotKeyCustomModifierRaw) ?? .command
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .en
    }

    private var selectedCustomHotKey: HotKeyChoice {
        customHotKeyChoices.first(where: { $0.keyCode == hotKeyCustomKeyCode }) ?? customHotKeyChoices[0]
    }

    private var selectedCustomKeyTitle: String {
        customHotKeyChoices.first(where: { $0.keyCode == hotKeyCustomKeyCode })?.title ?? "\(lh("hotkey.key")) \(hotKeyCustomKeyCode)"
    }

    private var introContent: some View {
        VStack(spacing: 16) {
            iconHero

            Text("Lighthouse")
                .font(.system(size: 36, weight: .bold))

            Text("Lightweight, pure Swift spotlight alternative for macOS.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Spacer(minLength: 0)

            featureCarousel

            Spacer(minLength: 0)
            
            HStack {
                Spacer(minLength: 0)
                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = .permissions
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
    }

    private var permissionsContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Initial Setup")
                        .font(.system(size: 26, weight: .bold))

                    Text("Choose permissions and shortcut behavior now. You can change this anytime in Settings.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    setupSectionTag("PERMISSIONS")
                    permissionRow(
                        title: "Notifications",
                        description: "Used for timer completion alerts.",
                        statusText: notificationsKnown ? (notificationsGranted ? lh("permission.allowed") : lh("permission.not_allowed")) : lh("permission.checking"),
                        statusColor: notificationsKnown ? (notificationsGranted ? .green : .orange) : .secondary,
                        action: openNotificationsSettings
                    )

                    permissionRow(
                        title: "Automation (Music/Spotify)",
                        description: "Used for play/pause, next/previous, and now playing info.",
                        statusText: automationStatus.title,
                        statusColor: automationStatus.color,
                        action: openAutomationSettings
                    )

                    permissionRow(
                        title: "Calendar",
                        description: "Used to show your upcoming event in the calendar panel.",
                        statusText: calendarStatus.title,
                        statusColor: calendarStatus.color,
                        action: {
                            Task {
                                await handleCalendarPermissionAction()
                            }
                        }
                    )

                    setupSectionTag("SHORTCUT")
                    shortcutSetupCard

                    HStack(spacing: 8) {
                        Text("You can change this anytime in")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("/settings")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 86)
            }

            HStack {
                Spacer(minLength: 0)
                Button(hasAtLeastOnePermission ? "Continue" : "Not now") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = .howItWorks
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func setupSectionTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.6)
    }

    private var shortcutSetupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(HotKeyMode.allCases) { mode in
                    let isSelected = hotKeyModeRaw == mode.rawValue
                    Button {
                        hotKeyModeRaw = mode.rawValue
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if hotKeyMode == .replaceSpotlight {
                HStack(spacing: 8) {
                    Text("Using Cmd + Space")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    openCircleButton(action: openSpotlightShortcutSettings)
                }
            } else if hotKeyMode == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(HotKeyModifier.allCases) { modifier in
                            let isSelected = hotKeyCustomModifierRaw == modifier.rawValue
                            Button {
                                hotKeyCustomModifierRaw = modifier.rawValue
                            } label: {
                                Text("\(modifier.symbol) \(modifier.title)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Button {
                            startHotKeyCapture()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isCapturingCustomKey ? "circle.fill" : "keyboard")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(isCapturingCustomKey ? Color.blue : Color.secondary)
                                Text(isCapturingCustomKey ? lh("hotkey.press_any_key") : "\(lh("hotkey.set_key")): \(selectedCustomKeyTitle)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)
                    }
                }
            } else {
                Text("Global shortcut is disabled.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var howItWorksContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How Lighthouse Works")
                .font(.system(size: 26, weight: .bold))

            Text("Type, run, and stay in flow. Lighthouse combines Spotlight-style search, chat-like history, and focused micro apps.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            introRow(
                symbol: "magnifyingglass",
                title: lh("onboarding.how.search.title"),
                description: lh("onboarding.how.search.description")
            )

            introRow(
                symbol: "command",
                title: lh("onboarding.how.slash.title"),
                description: lh("onboarding.how.slash.description")
            )

            introRow(
                symbol: "square.grid.2x2",
                title: lh("onboarding.how.builtin.title"),
                description: lh("onboarding.how.builtin.description")
            )

            introRow(
                symbol: "keyboard",
                title: lh("onboarding.how.global.title"),
                description: lh("onboarding.how.global.description")
            )

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Button("Got it, let me try it") {
                    onContinue()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
    }

    private func introRow(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func permissionRow(
        title: String,
        description: String,
        statusText: String,
        statusColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )

            openCircleButton(action: action)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func openCircleButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(Text("Open System Settings"))
    }

    private var welcomeBackground: some View {
        let theme = SearchThemeColor.charcoal
        return Group {
            if windowTransparencyEnabled && windowBlurEnabled {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.color.opacity(theme.overlayOpacity))
            } else if windowTransparencyEnabled {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.color.opacity(0.74))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.color)
            }
        }
    }

    private var iconHero: some View {
        ZStack {
            Group {
                if NSImage(named: NSImage.Name("StatusBarIcon")) != nil {
                    Image("StatusBarIcon")
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
    }

    private var featureCarousel: some View {
        let feature = features[currentFeatureIndex]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.72)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: Color.blue.opacity(0.28), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(feature.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(2)
                        .frame(minHeight: 32, alignment: .topLeading)
                }
                .id(feature.id)
            }

            HStack(spacing: 5) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, _ in
                    Capsule(style: .continuous)
                        .fill(index == currentFeatureIndex ? Color.blue.opacity(0.9) : Color.primary.opacity(0.18))
                        .frame(width: index == currentFeatureIndex ? 16 : 6, height: 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 500, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack {
            if step != .intro {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if step == .permissions {
                            step = .intro
                        } else {
                            step = .permissions
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Back")
            } else {
                Color.clear
                    .frame(width: 24, height: 24)
            }

            Spacer(minLength: 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(WelcomeWindowDragHandle())
    }

    /// Shared permission-state refresh for onboarding setup step.
    @MainActor
    private func refreshNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsKnown = true
        notificationsGranted = settings.authorizationStatus == .authorized
        automationStatus = await detectAutomationPermission()
        calendarStatus = detectCalendarPermission()
    }

    /// Uses script probe to infer current Automation permission state.
    private func detectAutomationPermission() async -> PermissionState {
        let spotifyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false
        let musicRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty == false
        guard spotifyRunning || musicRunning else { return .notRequired }

        let target = spotifyRunning ? "Spotify" : "Music"
        let script = """
        tell application "\(target)"
            if it is running then
                get player state as string
            end if
        end tell
        """

        var error: NSDictionary?
        let nsScript = NSAppleScript(source: script)
        _ = nsScript?.executeAndReturnError(&error)
        guard let error else { return .allowed }

        let errNum = error[NSAppleScript.errorNumber] as? Int ?? 0
        let desc = (error[NSAppleScript.errorMessage] as? String ?? "").lowercased()
        if errNum == -1743 || desc.contains("not authorized") {
            return .denied
        }
        return .unknown
    }

    private func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
        ]
        openFirstAvailable(urls)
    }

    private func openNotificationsSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]
        openFirstAvailable(urls)
    }

    private func openCalendarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
        ]
        openFirstAvailable(urls)
    }

    /// Calendar row behavior in onboarding: request first, fallback to system settings.
    @MainActor
    private func handleCalendarPermissionAction() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            await requestCalendarPermission()
        } else {
            openCalendarSettings()
        }
        await refreshNotificationStatus()
    }

    /// Requests EventKit calendar permission during onboarding.
    @MainActor
    private func requestCalendarPermission() async {
        let store = EKEventStore()
        if #available(macOS 14.0, *) {
            _ = try? await store.requestFullAccessToEvents()
        } else {
            _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    private func openSpotlightShortcutSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ]
        openFirstAvailable(urls)
    }

    /// Starts temporary key capture when user selects custom shortcut setup.
    private func startHotKeyCapture() {
        stopHotKeyCapture()
        isCapturingCustomKey = true
        keyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let blocked: Set<UInt16> = [UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option), UInt16(kVK_Control)]
            if blocked.contains(event.keyCode) { return nil }
            hotKeyCustomKeyCode = Int(event.keyCode)
            stopHotKeyCapture()
            return nil
        }
    }

    /// Stops custom key capture and detaches event monitor.
    private func stopHotKeyCapture() {
        isCapturingCustomKey = false
        if let monitor = keyCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            keyCaptureMonitor = nil
        }
    }

    /// Maps EventKit authorization into local permission badge state.
    private func detectCalendarPermission() -> PermissionState {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .authorized, .fullAccess:
                return .allowed
            case .denied, .restricted, .writeOnly:
                return .denied
            case .notDetermined:
                return .unknown
            @unknown default:
                return .unknown
            }
        }
        switch status {
        case .authorized:
            return .allowed
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    /// Opens first available deep-link to System Settings section.
    private func openFirstAvailable(_ rawURLs: [String]) {
        for raw in rawURLs {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private enum PermissionState {
        case allowed
        case denied
        case notRequired
        case unknown

        var title: String {
            switch self {
            case .allowed: return lh("permission.allowed")
            case .denied: return lh("permission.not_allowed")
            case .notRequired: return lh("permission.not_required_now")
            case .unknown: return lh("permission.not_requested")
            }
        }

        var color: Color {
            switch self {
            case .allowed: return .green
            case .denied: return .orange
            case .notRequired: return .secondary
            case .unknown: return .secondary
            }
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.95), Color.blue.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.blue.opacity(0.35), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct WelcomeWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WelcomeDragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WelcomeDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
