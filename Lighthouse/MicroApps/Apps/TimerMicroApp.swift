import SwiftUI
import UserNotifications
import AppKit
import Combine

extension MicroApps {
    /// Countdown timer micro app with local notification on completion.
    struct CountdownTimerCard: View {
        @ObservedObject var model: CountdownTimerModel
        @State private var didInit = false

        private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

        private var progressFraction: Double {
            guard model.duration > 0 else { return 0 }
            return max(0, min(1, model.remaining / model.duration))
        }

        private var timerTint: Color {
            model.remaining <= 10 ? .red : .mint
        }

        var body: some View {
            MicroApps.card(
                title: lh("microapp.timer.title"),
                subtitle: model.label,
                icon: "hourglass",
                tint: model.remaining <= 10 ? .red : .mint
            ) {
                VStack(spacing: 8) {
                    Text(MicroApps.formatTime(model.remaining))
                        .font(.system(size: 33, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.remaining <= 10 ? .red : .primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .animation(.easeInOut(duration: 0.2), value: model.remaining <= 10)
                    MicroApps.statusBadge(
                        model.isRunning ? lh("microapp.stopwatch.running") : (model.remaining < model.duration ? lh("microapp.stopwatch.paused") : lh("microapp.stopwatch.ready")),
                        color: model.remaining <= 10 ? .red : (model.isRunning ? .mint : .secondary)
                    )
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

                ProgressView(value: progressFraction, total: 1)
                    .progressViewStyle(.linear)
                    .tint(timerTint)
                    .animation(.linear(duration: 0.5), value: progressFraction)

                HStack(spacing: 10) {
                    Button {
                        model.isRunning.toggle()
                    } label: {
                        Text(model.isRunning ? lh("common.pause") : (model.remaining < model.duration ? lh("common.resume") : lh("common.start")))
                    }
                    .buttonStyle(MicroApps.MicroAppActionButtonStyle(
                        tint: timerTint,
                        isPrimary: true
                    ))

                    Button {
                        model.remaining = model.duration
                        model.isRunning = false
                        model.didNotify = false
                    } label: {
                        Text(lh("common.reset"))
                    }
                    .buttonStyle(MicroApps.MicroAppActionButtonStyle(tint: .secondary, isPrimary: false))
                }
            }
            .onAppear {
                guard !didInit else { return }
                didInit = true
                Task { await requestNotifications() }
            }
            .onReceive(timer) { _ in
                guard model.isRunning, model.remaining > 0 else { return }
                model.remaining = max(0, model.remaining - 0.5)
                if model.remaining <= 0.001 {
                    model.isRunning = false
                    if !model.didNotify {
                        model.didNotify = true
                        notifyTimerFinished()
                    }
                }
            }
        }

        /// Ensures notifications are authorized before completion alert fires.
        private func requestNotifications() async {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }

        /// Plays local sound, emits in-app toast event, and pushes system notification when allowed.
        private func notifyTimerFinished() {
            if let sound = NSSound(named: "Glass") {
                sound.play()
            } else {
                NSSound.beep()
            }

            NotificationCenter.default.post(name: .timerFinished, object: nil)

            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .authorized else { return }

                let content = UNMutableNotificationContent()
                content.title = lh("microapp.timer.finished")
                content.body = lh("microapp.timer.finished.body")
                content.sound = .default
                if #available(macOS 12.0, *) {
                    content.interruptionLevel = .timeSensitive
                }

                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                _ = try? await center.add(request)
            }
        }
    }

    /// Generic error card used for invalid micro app input.
    struct InvalidInputCard: View {
        let title: String
        let subtitle: String
        let icon: String
        let message: String

        var body: some View {
            MicroApps.card(title: title, subtitle: subtitle, icon: icon, tint: .red) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.95))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
    }
}
