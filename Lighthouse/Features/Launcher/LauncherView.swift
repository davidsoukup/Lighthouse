import SwiftUI
import AppKit
import EventKit
import Combine

// MARK: - Main view

// MARK: - Main view

struct LauncherView: View {
    var onClose:        () -> Void        = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }

    private static let emptyHeight:    CGFloat = 60
    private static let mediaBarHeight: CGFloat = 72
    private static let calendarBarHeight: CGFloat = 40
    private static let maxListHeight:  CGFloat = 440
    private static let microAppsGuideHeight: CGFloat = 166

    @State private var listContentHeight:   CGFloat = 0
    @State private var searchBarH:          CGFloat = 0
    @State private var historyHeaderH:      CGFloat = 0

    /// Dynamically computes launcher height from currently visible sections.
    private var windowHeight: CGFloat {
        let mediaH: CGFloat = hasMediaBar ? Self.mediaBarHeight : 0
        let calendarH: CGFloat = hasCalendarBar ? Self.calendarBarHeight : 0
        let guideH: CGFloat = showsMicroAppsGuide ? Self.microAppsGuideHeight : 0
        // Use measured heights; fall back to empirical constants until first layout
        let sbH  = searchBarH  > 0 ? searchBarH  : Self.emptyHeight
        let hhH  = historyHeaderH > 0 ? historyHeaderH + 1 : 33  // +1 divider

        if isSearching && !searchResults.isEmpty {
            let listH = listContentHeight > 0 ? min(listContentHeight, Self.maxListHeight) : 0
            guard listH > 0 else { return mediaH + calendarH + sbH + guideH }
            return mediaH + calendarH + sbH + guideH + 1 + listH
        }
        if !isSearching && !messages.isEmpty && chatVisible {
            let listH = listContentHeight > 0 ? min(listContentHeight, Self.maxListHeight) : 0
            guard listH > 0 else { return mediaH + calendarH + sbH + guideH + hhH }
            return mediaH + calendarH + sbH + guideH + hhH + 1 + listH
        }
        if !isSearching && !messages.isEmpty {
            return mediaH + calendarH + sbH + guideH + hhH
        }
        return mediaH + calendarH + sbH + guideH
    }

    // Search
    @State private var query        = ""
    @State private var allApps:     [(name: String, path: String)] = []
    @State private var appResults:  [SearchResultItem] = []
    @State private var fileResults: [SearchResultItem] = []
    @State private var microAppResults:  [SearchResultItem] = []
    @State private var webResults:  [SearchResultItem] = []
    @State private var selectedIdx  = 0
    @State private var fileTask:    Task<Void, Never>? = nil
    @State private var activeMicroApp: String? = nil
    @State private var microAppArgs: String = ""
    @State private var showToast = false
    @State private var showMicroAppsGuide = false
    @State private var hoveredMicroAppKey: String? = nil
    @StateObject private var media = MediaController()
    @State private var calendarStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var nextCalendarEvent: EKEvent? = nil
    @State private var nextCalendarEventDay: String = ""
    @State private var calcResult: String? = nil
    @State private var isCalc: Bool = false
    @AppStorage("settings.mediaPanelEnabled") private var mediaPanelEnabled: Bool = true
    @AppStorage("settings.calendarPanelEnabled") private var calendarPanelEnabled: Bool = true
    @AppStorage("settings.calendarShowMeetButton") private var calendarShowMeetButton: Bool = true
    @AppStorage("settings.searchThemeColor") private var searchThemeColorRaw: String = SearchThemeColor.charcoal.rawValue
    @AppStorage("settings.windowBlurEnabled") private var windowBlurEnabled: Bool = true
    @AppStorage("settings.windowTransparencyEnabled") private var windowTransparencyEnabled: Bool = true
    @AppStorage("settings.appLanguage") private var appLanguageRaw: String = AppLanguage.en.rawValue

    private var searchTheme: SearchThemeColor {
        SearchThemeColor(rawValue: searchThemeColorRaw) ?? .charcoal
    }

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .en
    }

    // Chat
    @State private var messages:     [ChatMessage] = []
    @State private var isLoading     = false
    @State private var chatVisible   = false

    private enum FocusTarget: Hashable { case search, args }
    @FocusState private var focused: FocusTarget?

    private var searchResults: [SearchResultItem] { appResults + fileResults + microAppResults + webResults }
    private var isSearching: Bool { !query.isEmpty }
    private var showsMicroAppsGuide: Bool { showMicroAppsGuide && activeMicroApp == nil && !isSearching }
    private var utilityMicroApps: [(key: String, desc: String, symbol: String)] {
        knownMicroApps.filter { $0.key == "timer" || $0.key == "stopwatch" }
    }
    private var systemMicroApps: [(key: String, desc: String, symbol: String)] {
        knownMicroApps.filter { $0.key != "timer" && $0.key != "stopwatch" }
    }

    // MARK: Body

    /// Main launcher layout with top panels, input row, results/history, and toast overlay.
    var body: some View {
        VStack(spacing: 0) {
            if hasMediaBar {
                mediaBar
                Divider().opacity(0.2)
            }
            if hasCalendarBar {
                calendarBar
                Divider().opacity(0.2)
            }
            searchBar
            if showsMicroAppsGuide {
                Divider().opacity(0.25)
                microAppsGuide
            }

            if isSearching {
                if !searchResults.isEmpty {
                    Divider().opacity(0.35)
                    spotlightResults
                        .transition(.opacity)
                }
            } else if !messages.isEmpty {
                Divider().opacity(0.35)
                historyHeader
                if chatVisible {
                    Divider().opacity(0.2)
                    messagesArea
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(blur)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) { toast }
        .onChange(of: windowHeight) { _, h in onHeightChange(h) }
        .onChange(of: chatVisible)  { _, v in if !v { listContentHeight = 0 } }
        .onAppear {
            focused     = .search
            messages    = HistoryStore.shared.messages
            chatVisible = false
            Task { await loadApps() }
            Task { await refreshCalendarPanel() }
            DispatchQueue.main.async { onHeightChange(self.windowHeight) }
        }
        .onReceive(calendarRefreshTicker) { _ in
            guard hasCalendarBar else { return }
            Task { await refreshCalendarPanel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .timerFinished)) { _ in
            withAnimation(.spring(duration: 0.35)) { showToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.25)) { showToast = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            focused = .search
        }
        .environment(\.locale, appLanguage.locale)
    }

    private var blur: some View {
        ZStack {
            if windowTransparencyEnabled && windowBlurEnabled {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(searchTheme.color.opacity(searchTheme.overlayOpacity))
            } else if windowTransparencyEnabled {
                RoundedRectangle(cornerRadius: 16).fill(searchTheme.color.opacity(0.74))
            } else {
                RoundedRectangle(cornerRadius: 16).fill(searchTheme.color)
            }
            RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private let calendarRefreshTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var mediaBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Artwork
                Group {
                    if let art = media.artwork {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: media.appName == "Spotify" ? "music.note.list" : "music.note")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.primary.opacity(0.07))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Track info
                VStack(alignment: .leading, spacing: 1) {
                    if media.needsPermission {
                        Text("\(lh("launcher.media.allow_prefix")) \(media.appName.isEmpty ? lh("common.music") : media.appName) \(lh("launcher.media.allow_suffix"))")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("Grant Automation access in System Settings")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(media.title.isEmpty ? lh("launcher.media.not_playing") : media.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(media.artist.isEmpty ? media.appName : media.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Controls
                if media.needsPermission {
                    Button("Enable") { media.requestPermission() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    HStack(spacing: 16) {
                        if media.duration > 0 {
                            Text("\(formatTime(media.position)) / \(formatTime(media.duration))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Button { media.previousTrack() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)

                        Button { media.togglePlayPause() } label: {
                            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)

                        Button { media.nextTrack() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var calendarBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: 0.5)
            }
            .frame(width: 24, height: 24)

            Text(calendarInlineTitle)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if calendarStatus == .notDetermined {
                Button("Enable") {
                    Task {
                        await requestCalendarPermission()
                        await refreshCalendarPanel()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if isCalendarAccessDenied(calendarStatus) {
                Button("Open") {
                    openCalendarSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let event = nextCalendarEvent {
                if calendarShowMeetButton, let meetURL = googleMeetURL(for: event) {
                    if isMeetJoinWindowOpen(for: event) {
                        HStack(spacing: 8) {
                            calendarInfoBadge(text: calendarSubtitle(for: event, dayPrefix: nextCalendarEventDay))
                            Button {
                                NSWorkspace.shared.open(meetURL)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Join Google Meet")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(searchTheme.accentColor.opacity(0.16))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(searchTheme.accentColor.opacity(0.34), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        calendarInfoBadge(text: calendarSubtitle(for: event, dayPrefix: nextCalendarEventDay))
                    }
                } else {
                    calendarInfoBadge(text: calendarSubtitle(for: event, dayPrefix: nextCalendarEventDay))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Small capsule row used for calendar time/status metadata.
    private func calendarInfoBadge(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }

    /// Formats media progress as `m:ss`.
    private func formatTime(_ t: TimeInterval) -> String {
        guard t > 0 else { return "--:--" }
        let total = Int(t.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }


    private var toast: some View {
        Group {
            if showToast {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Timer finished")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        let isCompact = !hasMediaBar && !hasCalendarBar && !isSearching && messages.isEmpty
        return HStack(spacing: 14) {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.regular).tint(.secondary)
                } else {
                    Image(systemName: isCalc ? "plus.forwardslash.minus" : (query.hasPrefix("/") ? "app.shadow" : "magnifyingglass"))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26)

            if let cmd = activeMicroApp {
                HStack(spacing: 8) {
                    Text("/\(cmd)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        )

                    TextField(microAppArgsPlaceholders[cmd] ?? lh("common.value"), text: $microAppArgs)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22))
                        .focused($focused, equals: .args)
                        .onSubmit { handleSubmit() }
                        .onChange(of: microAppArgs) { _, args in
                            query = "/\(cmd)" + (args.isEmpty ? "" : " \(args)")
                        }
                        .onKeyPress(.escape) {
                            activeMicroApp = nil
                            microAppArgs = ""
                            query = ""
                            clearResults()
                            focused = .search
                            return .handled
                        }
                }
            } else {
                TextField(
                    query.hasPrefix("/") ? lh("launcher.micro_apps") : lh("app.name"),
                    text: $query
                )
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($focused, equals: .search)
                .onSubmit       { handleSubmit() }
                .onChange(of: query) { _, q in selectedIdx = 0; doSearch(q); updateCalc(q) }
                .onKeyPress(.upArrow)   { selectedIdx = max(0, selectedIdx - 1); return .handled }
                .onKeyPress(.downArrow) { selectedIdx = min(searchResults.count - 1, selectedIdx + 1); return .handled }
                .onKeyPress(.escape)    {
                    if !query.isEmpty { query = ""; clearResults() } else { onClose() }
                    return .handled
                }
            }

            calcResultBadge

            Button {
                showMicroAppsGuide.toggle()
            } label: {
                Image(systemName: showMicroAppsGuide ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(showMicroAppsGuide ? Color.blue : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(showMicroAppsGuide ? Color.blue.opacity(0.14) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(showMicroAppsGuide ? Color.blue.opacity(0.32) : Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Show micro apps")

            if !query.isEmpty || activeMicroApp != nil {
                Button {
                    activeMicroApp = nil
                    microAppArgs = ""
                    query = ""
                    clearResults()
                    focused = .search
                    isCalc = false
                    calcResult = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, isCompact ? 8 : (hasMediaBar ? 16 : 12))
        .transaction { $0.animation = nil }
    }

    private var microAppsGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Micro apps")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 2)

            microAppsSection(title: lh("launcher.section.utility").uppercased(), items: utilityMicroApps)
            microAppsSection(title: lh("launcher.section.system").uppercased(), items: systemMicroApps)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    /// Grid section for one micro-app category (utility/system).
    private func microAppsSection(title: String, items: [(key: String, desc: String, symbol: String)]) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .leading),
            count: 4
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(items, id: \.key) { item in
                    let tint = microAppTint(for: item.key)
                    let isHovered = hoveredMicroAppKey == item.key
                    Button {
                        showMicroAppsGuide = false
                        if microAppsAcceptingArgs.contains(item.key) {
                            activeMicroApp = item.key
                            microAppArgs = ""
                            query = "/\(item.key)"
                            clearResults()
                            focused = .args
                        } else {
                            query = ""
                            clearResults()
                            sendMicroApp("/\(item.key)")
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(tint.opacity(0.78))
                                )
                                .shadow(color: tint.opacity(0.18), radius: 4, y: 2)

                            Text("/\(item.key)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isHovered ? searchTheme.accentColor.opacity(0.18) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isHovered ? searchTheme.accentColor.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(item.desc)
                    .onHover { hovering in
                        hoveredMicroAppKey = hovering ? item.key : (hoveredMicroAppKey == item.key ? nil : hoveredMicroAppKey)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Stable accent mapping per micro app for icon background color.
    private func microAppTint(for key: String) -> Color {
        switch key {
        case "timer":
            return .mint
        case "stopwatch":
            return .cyan
        case "cpu":
            return .purple
        case "memory":
            return .orange
        case "uptime":
            return .indigo
        case "settings", "storage":
            return .blue
        default:
            return searchTheme.accentColor
        }
    }

    private var calcResultBadge: some View {
        Text(isCalc ? (calcResult ?? "") : "")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(isCalc ? .secondary : Color.clear)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCalc ? Color.primary.opacity(0.06) : Color.clear)
            )
            .frame(width: 80, alignment: .trailing)
    }

    private var hasMediaBar: Bool {
        mediaPanelEnabled && (media.isPlaying || media.appRunning)
    }

    private var hasCalendarBar: Bool {
        calendarPanelEnabled
    }

    /// Treats denied/restricted/writeOnly states as non-readable calendar access.
    private func isCalendarAccessDenied(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .denied || status == .restricted || status == .writeOnly
        }
        return status == .denied || status == .restricted
    }

    /// Refreshes top calendar panel with the next relevant event (today/tomorrow window).
    @MainActor
    private func refreshCalendarPanel() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarStatus = status

        guard MicroApps.hasCalendarReadAccess(status) else {
            nextCalendarEvent = nil
            nextCalendarEventDay = ""
            return
        }

        let store = EKEventStore()
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        guard let dayAfterTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday) else {
            nextCalendarEvent = nil
            nextCalendarEventDay = ""
            return
        }

        let predicate = store.predicateForEvents(withStart: now, end: dayAfterTomorrow, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
        let event = events.first(where: { !$0.isAllDay }) ?? events.first

        nextCalendarEvent = event

        if let event {
            if Calendar.current.isDateInToday(event.startDate) {
                nextCalendarEventDay = lh("calendar.today")
            } else if Calendar.current.isDateInTomorrow(event.startDate) {
                nextCalendarEventDay = lh("calendar.tomorrow")
            } else {
                nextCalendarEventDay = ""
            }
        } else {
            nextCalendarEventDay = ""
        }
    }

    /// Requests EventKit calendar read permission.
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

    /// Opens the Calendar privacy pane in System Settings.
    private func openCalendarSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Formats calendar event time range with optional Today/Tomorrow prefix.
    private func calendarSubtitle(for event: EKEvent, dayPrefix: String) -> String {
        if event.isAllDay {
            return dayPrefix.isEmpty ? lh("calendar.all_day") : "\(dayPrefix), \(lh("calendar.all_day").lowercased())"
        }
        let formatter = DateFormatter()
        formatter.locale = appLanguage.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let range = "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
        return dayPrefix.isEmpty ? range : "\(dayPrefix), \(range)"
    }

    /// Join button is available only 15 minutes before start and during the event.
    private func isMeetJoinWindowOpen(for event: EKEvent) -> Bool {
        let now = Date()
        let joinWindowStart = event.startDate.addingTimeInterval(-15 * 60)
        return now >= joinWindowStart && now <= event.endDate
    }

    /// Extracts the first usable Google Meet URL from event URL/notes/location.
    private func googleMeetURL(for event: EKEvent) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let candidates: [String] = [
            event.url?.absoluteString ?? "",
            event.notes ?? "",
            event.location ?? ""
        ]

        for text in candidates where !text.isEmpty {
            if let direct = firstDirectMeetURL(in: text) {
                return direct
            }
            if let found = firstGoogleMeetURL(in: text, detector: detector) {
                return found
            }
        }
        return nil
    }

    /// Link detector path for standard URLs and text-extracted URLs.
    private func firstGoogleMeetURL(in text: String, detector: NSDataDetector?) -> URL? {
        guard !text.isEmpty else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        for match in matches {
            if let url = match.url, let meetURL = normalizedGoogleMeetURL(from: url) {
                return meetURL
            }
        }
        // Fallback for raw links without scheme (e.g. "meet.google.com/abc-defg-hij")
        if let raw = firstMeetCodeURLString(in: text), let url = URL(string: "https://\(raw)"),
           let meetURL = normalizedGoogleMeetURL(from: url) {
            return meetURL
        }
        // Fallback for g.co/meet short links written as plain text.
        if let raw = firstGCoMeetURLString(in: text), let url = URL(string: "https://\(raw)"),
           let meetURL = normalizedGoogleMeetURL(from: url) {
            return meetURL
        }
        return nil
    }

    /// Normalizes known Google Meet URL variants (direct, g.co, redirected google.com URL).
    private func normalizedGoogleMeetURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "meet.google.com" || host.hasSuffix(".meet.google.com") {
            return url
        }

        if (host == "g.co" || host == "www.g.co"),
           url.path.lowercased().hasPrefix("/meet") {
            return url
        }

        // Some calendars store redirected links like:
        // https://www.google.com/url?q=https://meet.google.com/...
        if host.hasSuffix("google.com"),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for key in ["q", "url", "u", "link"] {
                if let value = queryItems.first(where: { $0.name.lowercased() == key })?.value {
                    let decoded = value.removingPercentEncoding ?? value
                    if let nestedURL = URL(string: decoded),
                       let meetURL = normalizedGoogleMeetURL(from: nestedURL) {
                        return meetURL
                    }
                }
            }
        }

        return nil
    }

    /// Fallback matcher for raw `meet.google.com/abc-defg-hij` patterns.
    private func firstMeetCodeURLString(in text: String) -> String? {
        let pattern = #"meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange]).lowercased()
    }

    /// Fallback matcher for g.co/meet short links in plain text.
    private func firstGCoMeetURLString(in text: String) -> String? {
        let pattern = #"(?:www\.)?g\.co/meet(?:/[a-z0-9\-_/]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange]).lowercased()
    }

    /// Direct matcher for fully formed Meet links with/without scheme.
    private func firstDirectMeetURL(in text: String) -> URL? {
        let pattern = #"(?:https?://)?meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        let raw = String(text[swiftRange]).lowercased()
        let normalized = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://\(raw)"
        return URL(string: normalized)
    }

    private var calendarInlineTitle: String {
        if calendarStatus == .notDetermined {
            return lh("calendar.access_needed")
        }
        if isCalendarAccessDenied(calendarStatus) {
            return lh("calendar.access_denied")
        }
        if let event = nextCalendarEvent {
            return event.title.isEmpty ? lh("calendar.untitled_event") : event.title
        }
        return lh("calendar.no_upcoming_events")
    }

    // MARK: Spotlight results

    private var spotlightResults: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section(lh("launcher.section.applications"), items: appResults)
                    section(lh("launcher.section.files"),  items: fileResults)
                    section(lh("launcher.section.micro_apps"),  items: microAppResults)
                    section(lh("launcher.section.web"), items: webResults)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { listContentHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in listContentHeight = h }
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(max(listContentHeight, 1), Self.maxListHeight))
            .onChange(of: selectedIdx) { _, i in
                if let item = searchResults[safe: i] {
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(item.id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    /// Generic results section renderer used by apps/files/micro apps/web groups.
    private func section(_ title: String, items: [SearchResultItem]) -> some View {
        if !items.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 3)
            ForEach(items) { item in
                let idx = searchResults.firstIndex(of: item) ?? 0
                ResultRow(item: item, isSelected: idx == selectedIdx)
                    .id(item.id)
                    .onTapGesture { activate(item) }
            }
        }
    }

    // MARK: History header (always visible when messages exist)

    private var historyHeader: some View {
        HStack {
            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                HistoryStore.shared.clear()
                messages = []
                chatVisible = false
                focused = .search
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete history")
            .padding(.trailing, 8)

            Image(systemName: chatVisible ? "chevron.down" : "chevron.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .padding(.top, 2)
        .contentShape(Rectangle())
        .onTapGesture { chatVisible.toggle() }
    }

    // MARK: Messages area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg).id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { listContentHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in listContentHeight = h }
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(max(listContentHeight, 1), Self.maxListHeight))
            .onAppear { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
    }

    // MARK: Actions

    /// Handles Enter key based on current mode (active micro app, slash submit, selected result).
    private func handleSubmit() {
        if let cmd = activeMicroApp {
            let full = "/\(cmd)" + (microAppArgs.isEmpty ? "" : " \(microAppArgs)")
            sendMicroApp(full)
            activeMicroApp = nil
            microAppArgs = ""
            query = ""
            clearResults()
            return
        }

        if let parsed = parseMicroAppForSubmit(query) {
            sendMicroApp(parsed)
            query = ""
            clearResults()
            return
        }
        guard !searchResults.isEmpty else { return }
        activate(searchResults[safe: selectedIdx] ?? searchResults[0])
    }

    /// Activates selected search result item.
    private func activate(_ item: SearchResultItem) {
        switch item {
        case .app(_, let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init(), completionHandler: nil)
            onClose()
        case .file(_, let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            onClose()
        case .microApp(let key, _, _):
            if microAppsAcceptingArgs.contains(key) {
                activeMicroApp = key
                microAppArgs = ""
                query = "/\(key)"
                clearResults()
                DispatchQueue.main.async { focused = .args }
            } else {
                query = ""; clearResults()
                sendMicroApp("/\(key)")
            }
        case .web(let q):
            query = ""; clearResults()
            sendWebSearch(q)
        }
    }

    /// Sends slash micro app invocation and stores request/response in history.
    private func sendMicroApp(_ cmd: String) {
        let userMsg = ChatMessage(content: .text(cmd), isUser: true)
        messages.append(userMsg)
        HistoryStore.shared.add(userMsg)
        chatVisible = true   // auto-open on new message
        isLoading = true

        Task {
            let result = await MicroAppHandler.shared.handle(cmd)
            isLoading = false
            let sysMsg = ChatMessage(content: result, isUser: false)
            messages.append(sysMsg)
            HistoryStore.shared.add(sysMsg)
        }
    }

    // MARK: Search logic

    /// Core search router for app/file/micro-app modes.
    private func doSearch(_ q: String) {
        fileTask?.cancel(); fileTask = nil
        guard !q.isEmpty else { clearResults(); return }

        if let parsed = parseMicroAppEntry(q) {
            activeMicroApp = parsed.microApp
            microAppArgs = parsed.args
            clearResults()
            DispatchQueue.main.async { focused = .args }
            isCalc = false
            calcResult = nil
            return
        }

        if q.hasPrefix("/") {
            appResults = []; fileResults = []
            let cmdQ = String(q.dropFirst()).lowercased()
            microAppResults = knownMicroApps
                .filter { cmdQ.isEmpty || $0.key.hasPrefix(cmdQ) || $0.desc.localizedCaseInsensitiveContains(cmdQ) }
                .map { .microApp(key: $0.key, desc: $0.desc, symbol: $0.symbol) }
            webResults = []
        } else {
            microAppResults = []
            let lower = q.lowercased()
            appResults = allApps
                .filter { $0.name.lowercased().contains(lower) }
                .prefix(5)
                .map { .app(name: $0.name, path: $0.path) }

            fileTask = Task {
                let paths = await runMdfind(q)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    fileResults = paths.prefix(6).map {
                        .file(name: URL(fileURLWithPath: $0).lastPathComponent, path: $0)
                    }
                    updateWebFallback(q)
                }
            }
            updateWebFallback(q)
        }
    }

    /// Clears all transient search result lists and pending file task.
    private func clearResults() {
        fileTask?.cancel(); fileTask = nil
        appResults = []; fileResults = []; microAppResults = []; webResults = []
        listContentHeight = 0
    }

    /// Parses `/timer ...` style typed argument entry while user is still editing input.
    private func parseMicroAppEntry(_ q: String) -> (microApp: String, args: String)? {
        guard q.hasPrefix("/") else { return nil }
        let trimmed = String(q.dropFirst())
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let cmd = parts.first?.lowercased(),
              microAppsAcceptingArgs.contains(cmd) else { return nil }
        let args = parts.count > 1 ? String(parts[1]) : ""
        if q.contains(" ") { return (cmd, args) }
        return nil
    }

    /// Validates slash submission against known micro apps before execution.
    private func parseMicroAppForSubmit(_ q: String) -> String? {
        guard q.hasPrefix("/") else { return nil }
        let trimmed = String(q.dropFirst())
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let cmd = parts.first?.lowercased(),
              knownMicroApps.contains(where: { $0.key == cmd }) else { return nil }
        if microAppsAcceptingArgs.contains(cmd) {
            if parts.count > 1 { return "/" + trimmed }
            return nil
        }
        return "/\(cmd)"
    }

    /// Shows web fallback only when not in slash-micro-app mode and not in calculator mode.
    private func updateWebFallback(_ q: String) {
        guard !q.isEmpty, !q.hasPrefix("/"), activeMicroApp == nil, !isCalc else {
            webResults = []
            return
        }
        webResults = [.web(query: q)]
    }

    /// Executes Brave web search and appends card response to history.
    private func sendWebSearch(_ q: String) {
        let userMsg = ChatMessage(content: .text("\(lh("web.searched_prefix")): \(q)"), isUser: true)
        messages.append(userMsg)
        HistoryStore.shared.add(userMsg)
        chatVisible = true
        isLoading = true

        Task {
            let results = await WebSearchClient.search(query: q)
            isLoading = false
            let sysMsg = ChatMessage(content: .view(AnyView(WebResultsCard(query: q, results: results))), isUser: false)
            messages.append(sysMsg)
            HistoryStore.shared.add(sysMsg)
        }
    }

    /// Lightweight inline calculator path (`1+2`, `12/3`, etc.).
    private func updateCalc(_ q: String) {
        guard activeMicroApp == nil else {
            isCalc = false
            calcResult = nil
            return
        }
        if let result = CalcEvaluator.evaluate(q) {
            isCalc = true
            calcResult = result
        } else {
            isCalc = false
            calcResult = nil
        }
        updateWebFallback(q)
    }

    // MARK: Loaders

    /// Loads installed apps from standard app directories.
    private func loadApps() async {
        allApps = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let dirs = ["/Applications", "/System/Applications",
                            "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
                var result: [(String, String)] = []
                for dir in dirs {
                    guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                    for item in items where item.hasSuffix(".app") {
                        result.append((item.replacingOccurrences(of: ".app", with: ""), "\(dir)/\(item)"))
                    }
                }
                continuation.resume(returning: result.sorted {
                    $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
                })
            }
        }
        if !query.isEmpty { doSearch(query) }
    }

    /// File lookup via Spotlight `mdfind` limited to user home.
    private func runMdfind(_ q: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError  = Pipe()
                task.launchPath     = "/usr/bin/mdfind"
                task.arguments      = ["-name", q, "-onlyin", NSHomeDirectory()]
                try? task.run()
                task.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let results = out
                    .components(separatedBy: "\n")
                    .filter { path in
                        guard !path.isEmpty, !path.hasSuffix(".app") else { return false }
                        let parts = URL(fileURLWithPath: path).pathComponents
                        // skip hidden files and Library/cache dirs
                        return !parts.contains(where: { $0.hasPrefix(".") })
                            && !parts.contains("Library")
                    }
                continuation.resume(returning: results)
            }
        }
    }
}

// MARK: - Helpers

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Notification.Name {
    static let focusSearchField = Notification.Name("lighthouse.focus.search")
}
