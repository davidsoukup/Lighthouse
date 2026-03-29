import Foundation
import Combine
import AppKit

final class MediaController: ObservableObject {
    @Published var isPlaying = false
    @Published var title = ""
    @Published var artist = ""
    @Published var appName = ""
    @Published var appRunning = false
    @Published var needsPermission = false
    @Published var lastError = ""
    @Published var artwork: NSImage? = nil
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var ticker: AnyCancellable?
    private var isRefreshing = false
    private var lastArtworkURL: String = ""

    init() {
        refreshAsync()
        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshAsync() }
    }

    /// Toggles play/pause for the currently selected media app (Spotify or Music).
    func togglePlayPause() {
        runControlScript(for: appName, command: "playpause")
    }

    /// Moves to next track in the active media app.
    func nextTrack() {
        runControlScript(for: appName, command: "next track")
    }

    /// Moves to previous track in the active media app.
    func previousTrack() {
        runControlScript(for: appName, command: "previous track")
    }

    /// Polls now-playing state in background and applies result on main actor.
    private func refreshAsync() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let spotifyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false
            let musicRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty == false
            let info = self.queryNowPlaying(app: "Music") ?? self.queryNowPlaying(app: "Spotify")
            await MainActor.run {
                if let info {
                    self.isPlaying = info.state == "playing"
                    self.appName = info.app
                    self.title = info.title
                    self.artist = info.artist
                    self.position = info.position
                    self.duration = info.duration
                    self.appRunning = true
                    self.needsPermission = false
                    if info.artworkURL != self.lastArtworkURL {
                        self.lastArtworkURL = info.artworkURL
                        self.loadArtwork(from: info.artworkURL)
                    }
                } else {
                    self.isPlaying = false
                    self.appName = ""
                    self.title = ""
                    self.artist = ""
                    self.position = 0
                    self.duration = 0
                    self.appRunning = spotifyRunning || musicRunning
                    self.needsPermission = self.appRunning
                    self.artwork = nil
                    self.lastArtworkURL = ""
                }
                self.isRefreshing = false
            }
        }
    }

    /// Reads metadata from AppleScript for a given media app and parses it into strongly-typed fields.
    private func queryNowPlaying(app: String) -> (app: String, title: String, artist: String, state: String, artworkURL: String, position: TimeInterval, duration: TimeInterval)? {
        let script = """
        tell application \"\(app)\"
            if it is running then
                set trackName to name of current track
                set artistName to artist of current track
                set pState to player state as string
                set pos to player position
                if \"\(app)\" is \"Spotify\" then
                    set artURL to artwork url of current track
                    set durMs to duration of current track
                    set durSec to (durMs / 1000)
                else
                    set artURL to \"\"
                    set durSec to duration of current track
                end if
                return \"\(app)||\" & trackName & \"||\" & artistName & \"||\" & pState & \"||\" & artURL & \"||\" & pos & \"||\" & durSec
            end if
        end tell
        return \"\"
        """
        guard let result = runAppleScript(script), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "||")
        if parts.count >= 7 {
            let pos = parseNumber(parts[5])
            let dur = parseNumber(parts[6])
            return (app: parts[0], title: parts[1], artist: parts[2], state: parts[3], artworkURL: parts[4], position: pos, duration: dur)
        }
        return nil
    }

    /// Sends transport command (play/pause/next/previous) via AppleScript.
    private func runControlScript(for app: String, command: String) {
        guard !app.isEmpty else { return }
        let script = """
        tell application \"\(app)\"
            if it is running then
                \(command)
            end if
        end tell
        """
        _ = runAppleScript(script)
    }

    /// Triggers Automation permission prompt by requesting safe reads from the target app.
    func requestPermission() {
        let target = appName.isEmpty ? "Spotify" : appName
        let script = """
        tell application \"\(target)\"
            if it is running then
                get name of current track
            end if
        end tell
        """
        Task { @MainActor in
            let (_, hadError, errText) = runAppleScriptWithError(script)
            if hadError { self.lastError = errText }
            if !hadError {
                self.needsPermission = false
                self.refreshAsync()
            }
        }
    }

    /// AppleScript helper returning only raw string result.
    private func runAppleScript(_ source: String) -> String? {
        let (result, _, _) = runAppleScriptWithError(source)
        return result
    }

    /// AppleScript helper that also surfaces permission/authorization errors.
    private func runAppleScriptWithError(_ source: String) -> (String?, Bool, String) {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&error)
        if let error {
            let desc = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            NSLog("AppleScript error: %@", desc)
            return (nil, true, desc)
        }
        return (output?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), false, "")
    }

    /// Loads album art from URL asynchronously and caches it in published state.
    private func loadArtwork(from urlString: String) {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            artwork = nil
            return
        }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            if let data = try? Data(contentsOf: url),
               let img = NSImage(data: data) {
                await MainActor.run { self.artwork = img }
            } else {
                await MainActor.run { self.artwork = nil }
            }
        }
    }

    /// Converts potentially localized numeric strings to Double.
    private func parseNumber(_ raw: String) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }
}
