import SwiftUI
import AppKit
import UserNotifications
import Carbon
import EventKit

struct SettingsView: View {
    var onClose: () -> Void = {}
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

    @State private var apiKeyInput: String = ""
    @State private var savedKey: String? = BraveAPIKeyStore.load()
    @State private var isEditing: Bool = false
    @State private var saveStatus: String? = nil
    @State private var showResetConfirmation: Bool = false
    @State private var notificationsGranted: Bool = false
    @State private var notificationsKnown: Bool = false
    @State private var automationStatus: PermissionState = .unknown
    @State private var calendarStatus: PermissionState = .unknown
    @State private var permissionsActionStatus: String? = nil
    @State private var isCapturingCustomKey: Bool = false
    @State private var keyCaptureMonitor: Any? = nil
    @AppStorage("settings.mediaPanelEnabled") private var mediaPanelEnabled: Bool = true
    @AppStorage("settings.calendarPanelEnabled") private var calendarPanelEnabled: Bool = true
    @AppStorage("settings.calendarShowMeetButton") private var calendarShowMeetButton: Bool = true
    @AppStorage("settings.searchThemeColor") private var searchThemeColorRaw: String = SearchThemeColor.charcoal.rawValue
    @AppStorage("settings.windowBlurEnabled") private var windowBlurEnabled: Bool = true
    @AppStorage("settings.windowTransparencyEnabled") private var windowTransparencyEnabled: Bool = true
    @AppStorage("settings.hotKey.mode") private var hotKeyModeRaw: String = HotKeyMode.replaceSpotlight.rawValue
    @AppStorage("settings.hotKey.customModifier") private var hotKeyCustomModifierRaw: String = HotKeyModifier.command.rawValue
    @AppStorage("settings.hotKey.customKeyCode") private var hotKeyCustomKeyCode: Int = Int(kVK_Space)
    @AppStorage("settings.appLanguage") private var appLanguageRaw: String = AppLanguage.en.rawValue

    private struct HotKeyChoice: Identifiable {
        let id: String
        let title: String
        let keyCode: Int
        let symbol: String
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

    private var selectedSearchTheme: SearchThemeColor {
        SearchThemeColor(rawValue: searchThemeColorRaw) ?? .charcoal
    }

    private var hotKeyMode: HotKeyMode {
        get { HotKeyMode(rawValue: hotKeyModeRaw) ?? .replaceSpotlight }
        set { hotKeyModeRaw = newValue.rawValue }
    }

    private var hotKeyModifier: HotKeyModifier {
        get { HotKeyModifier(rawValue: hotKeyCustomModifierRaw) ?? .command }
        set { hotKeyCustomModifierRaw = newValue.rawValue }
    }

    private var selectedCustomHotKey: HotKeyChoice {
        customHotKeyChoices.first(where: { $0.keyCode == hotKeyCustomKeyCode }) ?? customHotKeyChoices[0]
    }

    private var selectedCustomKeyTitle: String {
        customHotKeyChoices.first(where: { $0.keyCode == hotKeyCustomKeyCode })?.title ?? "\(lh("hotkey.key")) \(hotKeyCustomKeyCode)"
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .en
    }

    /// Main settings layout with grouped cards and persisted toggles.
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionTag("API KEYS & INTEGRATIONS")
                    apiKeyCard

                    if let saveStatus {
                        Text(saveStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    sectionTag("LANGUAGE")
                    languageCard

                    sectionTag("OPTIONS")
                    appearanceCard
                    hotKeyCard
                    permissionsCard
                    mediaPanelCard
                    resetCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .frame(width: 760, height: 520)
        .confirmationDialog(
            "Reset the app to factory settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                NotificationCenter.default.post(name: .factoryResetRequested, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the Brave API key, restore default options, and show the welcome window again.")
        }
        .task {
            await refreshPermissionStates()
        }
        .onDisappear {
            stopHotKeyCapture()
        }
        .environment(\.locale, appLanguage.locale)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                Text("Manage app behavior, integrations, and keys.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(WindowDragHandle())
    }

    private func sectionTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.7)
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brave Search API")
                .font(.system(size: 15, weight: .semibold))

            Text("Each user stores their own API key locally on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let key = savedKey, !isEditing {
                Text(BraveAPIKeyStore.displayMask(for: key))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.disabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.06))
                    )

                HStack(spacing: 10) {
                    Button("Change key") {
                        isEditing = true
                        apiKeyInput = ""
                        saveStatus = nil
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Delete") {
                        _ = BraveAPIKeyStore.delete()
                        savedKey = nil
                        apiKeyInput = ""
                        isEditing = false
                        saveStatus = lh("settings.key.deleted")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                SecureField("BSA...", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Save") {
                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            saveStatus = lh("settings.key.empty")
                            return
                        }

                        if BraveAPIKeyStore.save(trimmed) {
                            savedKey = trimmed
                            apiKeyInput = ""
                            isEditing = false
                            saveStatus = lh("settings.key.saved")
                        } else {
                            saveStatus = lh("settings.key.save_failed")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                    if savedKey != nil {
                        Button("Cancel") {
                            isEditing = false
                            apiKeyInput = ""
                            saveStatus = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var panelBackground: some View {
        let theme = SearchThemeColor.charcoal
        return Group {
            if windowTransparencyEnabled && windowBlurEnabled {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.color.opacity(theme.overlayOpacity))
            } else if windowTransparencyEnabled {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.color.opacity(0.74))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.color)
            }
        }
    }

    private var mediaPanelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Panels")
                .font(.system(size: 15, weight: .semibold))

            Text("Enable or disable top panels in the main launcher window.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show media panel")
                    Text(mediaPanelEnabled ? lh("common.enabled") : lh("common.disabled"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $mediaPanelEnabled)
                    .labelsHidden()
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show calendar panel")
                    Text(calendarPanelEnabled ? lh("common.enabled") : lh("common.disabled"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $calendarPanelEnabled)
                    .labelsHidden()
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Google Meet button in calendar panel")
                    Text(calendarShowMeetButton ? lh("common.enabled") : lh("common.disabled"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $calendarShowMeetButton)
                    .labelsHidden()
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.system(size: 15, weight: .semibold))

            Text("Change the background tint of the main launcher/search window.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window blur")
                    Text(windowBlurEnabled ? lh("common.enabled") : lh("common.disabled"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $windowBlurEnabled)
                    .labelsHidden()
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Window transparency")
                    Text(windowTransparencyEnabled ? lh("common.enabled") : lh("common.disabled"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $windowTransparencyEnabled)
                    .labelsHidden()
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack(spacing: 10) {
                ForEach(SearchThemeColor.allCases, id: \.rawValue) { theme in
                    Button {
                        searchThemeColorRaw = theme.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                            Text(theme.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .frame(minWidth: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedSearchTheme == theme ? Color.white.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(selectedSearchTheme == theme ? Color.white.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language")
                .font(.system(size: 15, weight: .semibold))

            Text("Choose app language. Default is English.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(AppLanguage.allCases) { language in
                    let isSelected = appLanguageRaw == language.rawValue
                    Button {
                        appLanguageRaw = language.rawValue
                    } label: {
                        Text(language.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var hotKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcut")
                .font(.system(size: 15, weight: .semibold))

            Text("Choose how Lighthouse opens from keyboard.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            hotKeyModeSelector
            hotKeyModeDetails
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var hotKeyModeSelector: some View {
        HStack(spacing: 10) {
            ForEach(HotKeyMode.allCases) { mode in
                hotKeyModeChip(mode)
            }
        }
    }

    private func hotKeyModeChip(_ mode: HotKeyMode) -> some View {
        let isSelected = hotKeyModeRaw == mode.rawValue
        return Button {
            hotKeyModeRaw = mode.rawValue
        } label: {
            Text(mode.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var hotKeyModeDetails: some View {
        switch hotKeyMode {
        case .replaceSpotlight:
            spotlightShortcutInfo
        case .custom:
            customShortcutInfo
        case .none:
            noShortcutInfo
        }
    }

    private var spotlightShortcutInfo: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Using \u{2318} + Space")
                    .font(.system(size: 12, weight: .semibold))
                Text("Disable Spotlight shortcut in macOS to avoid conflict.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            openCircleButton(action: openSpotlightShortcutSettings)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var customShortcutInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modifier")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ForEach(HotKeyModifier.allCases) { modifier in
                    let isSelected = hotKeyCustomModifierRaw == modifier.rawValue
                    Button {
                        hotKeyCustomModifierRaw = modifier.rawValue
                    } label: {
                        Text("\(modifier.symbol) \(modifier.title)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    startHotKeyCapture()
                } label: {
                    shortcutChoiceButton(
                        title: lh("hotkey.key").uppercased(),
                        value: isCapturingCustomKey ? lh("hotkey.press_any_key") : selectedCustomKeyTitle,
                        trailingSymbol: isCapturingCustomKey ? "circle.fill" : "keyboard"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func shortcutChoiceButton(title: String, value: String, trailingSymbol: String?) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(trailingSymbol == "circle.fill" ? Color.blue : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 170, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Starts one-shot keyboard capture for custom global shortcut key.
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

    /// Stops custom key capture and removes local event monitor.
    private func stopHotKeyCapture() {
        isCapturingCustomKey = false
        if let monitor = keyCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            keyCaptureMonitor = nil
        }
    }

    private var noShortcutInfo: some View {
        Text("Global shortcut is disabled.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.system(size: 15, weight: .semibold))

            Text("Used for media controls, timer notifications, and calendar events.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Text("Notifications")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.90))
                Spacer(minLength: 6)
                permissionBadge(
                    text: notificationsKnown ? (notificationsGranted ? lh("permission.allowed") : lh("permission.not_allowed")) : lh("permission.checking"),
                    color: notificationsKnown ? (notificationsGranted ? .green : .orange) : .secondary
                )
                openCircleButton(action: openNotificationsSettings)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automation (Music/Spotify)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Text("Needed for play/pause, next/previous track, and now playing info.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer(minLength: 6)
                permissionBadge(text: automationStatus.title, color: automationStatus.color)
                openCircleButton(action: openAutomationSettings)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Text("Used to show your upcoming event in the calendar panel.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer(minLength: 6)
                permissionBadge(text: calendarStatus.title, color: calendarStatus.color)
                openCircleButton {
                    Task {
                        await handleCalendarPermissionAction()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            Button("Reset permissions") {
                Task {
                    await resetPermissions()
                    await refreshPermissionStates()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let permissionsActionStatus {
                Text(permissionsActionStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func permissionBadge(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
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

    /// Refreshes all permission statuses used in this view.
    @MainActor
    private func refreshPermissionStates() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationsKnown = true
        notificationsGranted = settings.authorizationStatus == .authorized

        automationStatus = await detectAutomationPermission()
        calendarStatus = detectCalendarPermission()
    }

    /// Best-effort Automation permission detection via lightweight AppleScript probe.
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

    /// Calendar row behavior: request permission first, then open system settings when needed.
    @MainActor
    private func handleCalendarPermissionAction() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            await requestCalendarPermission()
        } else {
            openCalendarSettings()
        }
        await refreshPermissionStates()
    }

    /// Requests calendar access from EventKit API.
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

    /// Tries multiple deep-link URLs and opens the first supported settings destination.
    private func openFirstAvailable(_ rawURLs: [String]) {
        for raw in rawURLs {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Resets TCC entries for app-level permissions used by Lighthouse.
    @MainActor
    private func resetPermissions() async {
        let bundleID = "dev.soukup.Lighthouse"
        let resetAppleEvents = runTCCReset(service: "AppleEvents", bundleID: bundleID)
        let resetNotifications = runTCCReset(service: "Notifications", bundleID: bundleID)
        let resetCalendar = runTCCReset(service: "Calendar", bundleID: bundleID)

        if resetAppleEvents && resetNotifications && resetCalendar {
            permissionsActionStatus = "\(lh("settings.permissions.reset.success.prefix")) \(bundleID). \(lh("settings.permissions.reset.success.suffix"))"
        } else {
            permissionsActionStatus = lh("settings.permissions.reset.failed")
        }
    }

    /// Reads current EventKit authorization and maps it to local permission UI state.
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

    /// Executes `tccutil reset` for one permission service.
    private func runTCCReset(service: String, bundleID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", service, bundleID]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
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

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Factory Reset")
                .font(.system(size: 15, weight: .semibold))

            Text("Restore the app to defaults and show onboarding again.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("Reset to factory settings", role: .destructive) {
                showResetConfirmation = true
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
