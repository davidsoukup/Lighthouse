import Foundation
import SwiftUI
import Combine
import UserNotifications
import AppKit
import EventKit

extension Notification.Name {
    static let timerFinished = Notification.Name("lighthouse.timer.finished")
    static let openSettingsWindow = Notification.Name("lighthouse.open.settings.window")
}

enum MicroApps {
    /// Main router for slash micro-app invocations.
    static func execute(_ microAppLine: String) async -> MessageContent {
        let parts = microAppLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let microAppKey = parts.first?.lowercased() ?? ""
        let args = parts.count > 1 ? String(parts[1]) : ""

        switch microAppKey {
        case "settings":
            await MainActor.run {
                NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
            }
            return .text(lh("microapp.opening_settings"))
        case "storage", "disk":
            return .view(AnyView(storage()))
        case "cpu":
            return .view(AnyView(CpuCard()))
        case "memory":
            return .view(AnyView(MemoryCard()))
        case "uptime":
            return .view(AnyView(UptimeCard()))
        case "stopwatch":
            return .stopwatch(StopwatchModel())
        case "timer":
            let parsed = args.trimmingCharacters(in: .whitespacesAndNewlines)
            if parsed.isEmpty {
                return .timer(CountdownTimerModel(duration: 300, label: "5m"))
            }
            if let dur = parseDuration(parsed) {
                return .timer(CountdownTimerModel(duration: dur, label: parsed))
            }
            return .view(AnyView(InvalidInputCard(
                title: lh("microapp.timer.title"),
                subtitle: lh("microapp.invalid_input"),
                icon: "hourglass.badge.exclamationmark",
                message: lh("microapp.timer.invalid_help")
            )))
        case "help":
            return .text(help())
        default:
            return .text(lh("microapp.unknown"))
        }
    }

    /// Human-readable micro-app summary returned by `/help`.
    static func help() -> String {
        lh("microapp.help")
    }

    /// Runs shell command asynchronously and returns stdout as text.
    static func shell(_ command: String) async -> String {
        await Task.detached(priority: .userInitiated) {
            let task = Process()
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            try? task.run()
            task.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }.value
    }

    /// Formats bytes into compact units (KB/MB/GB/TB).
    static func fmt(_ n: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(n)
        var i = 0
        while v >= 1024, i < units.count - 1 {
            v /= 1024
            i += 1
        }
        return String(format: "%.1f %@", v, units[i])
    }

    /// Shared compact label used in card stats rows.
    static func infoLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    /// Shared card shell used by all micro-app cards for consistent visual style.
    static func card(title: String, subtitle: String?, icon: String, tint: Color = .blue, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(tint.opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: tint.opacity(0.16), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider().opacity(0.18)
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.46))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.07), radius: 5, y: 3)
    }

    /// Shared key/value row used across micro-app cards.
    static func kvRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    /// Shared progress meter row used for percentage metrics.
    static func meterRow(_ title: String, _ value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(Int(value))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            ProgressView(value: value, total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    /// Shared action button style for micro-app primary/secondary actions.
    struct MicroAppActionButtonStyle: ButtonStyle {
        let tint: Color
        let isPrimary: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPrimary ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isPrimary ? AnyShapeStyle(tint.opacity(0.86)) : AnyShapeStyle(Color.white.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(isPrimary ? 0.18 : 0.12), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    /// Shared status badge for connected/running/paused-like states.
    static func statusBadge(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    struct CpuInfo {
        let user: Double
        let sys: Double
        let idle: Double
    }

    struct MemoryInfo {
        let used: Int64
        let free: Int64
        let total: Int64
        let pct: Int
    }

    struct UptimeInfo {
        let up: String
        let load: String
    }

    /// Reads one-shot CPU percentages from `top`.
    static func cpuInfo() async -> CpuInfo? {
        let out = await shell("top -l 1 -n 0 | grep 'CPU usage'")
        let cleaned = out.lowercased()
        let user = extractPct(cleaned, key: "user")
        let sys = extractPct(cleaned, key: "sys")
        let idle = extractPct(cleaned, key: "idle")
        if let user, let sys, let idle {
            return CpuInfo(user: user, sys: sys, idle: idle)
        }
        return nil
    }

    /// Reads memory pages via `vm_stat` and converts them into bytes and usage percentage.
    static func memoryInfo() async -> MemoryInfo? {
        let vmstat = await shell("vm_stat")
        var pageSize: Double = 4096
        var p = [String: Double]()

        for line in vmstat.components(separatedBy: "\n") {
            if line.contains("page size of") {
                pageSize = line.components(separatedBy: " ").compactMap(Double.init).first ?? 4096
            }
            let v = vmVal(line)
            if      line.contains("Pages free:")                        { p["free"] = v }
            else if line.contains("Pages active:")                      { p["active"] = v }
            else if line.contains("Pages inactive:")                    { p["inactive"] = v }
            else if line.contains("Pages wired down:")                  { p["wired"] = v }
            else if line.contains("Pages occupied by compressor:")      { p["compressed"] = v }
        }

        let used = ((p["active"] ?? 0) + (p["wired"] ?? 0) + (p["compressed"] ?? 0)) * pageSize
        let free = ((p["free"] ?? 0) + (p["inactive"] ?? 0)) * pageSize
        let total = used + free
        let pct = total > 0 ? Int(used / total * 100) : 0

        return MemoryInfo(used: Int64(used), free: Int64(free), total: Int64(total), pct: pct)
    }

    /// Parses uptime output into readable uptime + load values.
    static func uptimeInfo() async -> UptimeInfo? {
        let out = await shell("uptime")
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let upRange = trimmed.range(of: " up "),
           let loadRange = trimmed.range(of: "load averages:") {
            let upPart = trimmed[upRange.upperBound..<loadRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            let loadPart = trimmed[loadRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return UptimeInfo(up: upPart, load: loadPart)
        }
        return UptimeInfo(up: trimmed, load: "—")
    }

    /// Extracts trailing percentage number before a given token (e.g. `user`, `sys`, `idle`).
    static func extractPct(_ text: String, key: String) -> Double? {
        guard let range = text.range(of: key) else { return nil }
        let prefix = text[..<range.lowerBound]
        let parts = prefix.split(separator: " ")
        guard let last = parts.last else { return nil }
        let number = last.replacingOccurrences(of: "%", with: "")
        return Double(number)
    }

    /// Parses timer input formats like `5m`, `90s`, `1:30`, or plain seconds.
    static func parseDuration(_ input: String) -> TimeInterval? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { Int($0) ?? 0 }
            if parts.count == 2 {
                return TimeInterval(parts[0] * 60 + parts[1])
            }
            if parts.count == 3 {
                return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
            }
        }

        let lower = trimmed.lowercased()
        var total: Double = 0
        var current = ""
        for ch in lower {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                guard let value = Double(current) else { current = ""; continue }
                switch ch {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: break
                }
                current = ""
            }
        }
        if total > 0 { return total }
        if let value = Double(lower) { return value }
        return nil
    }

    /// Current EventKit auth status for calendar access.
    static func calendarAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Returns true only for statuses that allow reading calendar events.
    static func hasCalendarReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .authorized || status == .fullAccess
        }
        return status == .authorized
    }

    /// Formats timer values as `mm:ss` or `h:mm:ss`.
    static func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Formats stopwatch values as `mm:ss.cc` or `h:mm:ss`.
    static func formatTimePrecise(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let cs = Int((t - Double(total)) * 100)
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    /// Parses a `vm_stat` numeric line by stripping punctuation.
    static func vmVal(_ line: String) -> Double {
        guard let colon = line.firstIndex(of: ":") else { return 0 }
        let raw = line[line.index(after: colon)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
        return Double(raw) ?? 0
    }
}
