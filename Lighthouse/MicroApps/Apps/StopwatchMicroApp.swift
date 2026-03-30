import SwiftUI
import Combine

extension MicroApps {
    /// Stopwatch micro app card with live centisecond updates.
    struct StopwatchCard: View {
        @ObservedObject var model: StopwatchModel

        private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

        var body: some View {
            MicroApps.card(
                title: lh("microapp.stopwatch.title"),
                subtitle: model.isRunning ? lh("microapp.stopwatch.running") : (model.elapsed > 0 ? lh("microapp.stopwatch.paused") : lh("microapp.stopwatch.ready")),
                icon: "stopwatch",
                tint: .cyan
            ) {
                VStack(spacing: 8) {
                    Text(MicroApps.formatTimePrecise(model.elapsed))
                        .font(.system(size: 33, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    MicroApps.statusBadge(
                        model.isRunning ? lh("microapp.stopwatch.running") : (model.elapsed > 0 ? lh("microapp.stopwatch.paused") : lh("microapp.stopwatch.ready")),
                        color: model.isRunning ? .mint : .secondary
                    )
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

                HStack(spacing: 10) {
                    Button {
                        if model.isRunning {
                            model.isRunning = false
                        } else {
                            model.startDate = Date().addingTimeInterval(-model.elapsed)
                            model.isRunning = true
                        }
                    } label: {
                        Text(model.isRunning ? lh("common.pause") : lh("common.start"))
                    }
                    .buttonStyle(MicroApps.MicroAppActionButtonStyle(tint: .cyan, isPrimary: true))

                    Button {
                        model.startDate = Date()
                        model.elapsed = 0
                        model.isRunning = false
                    } label: {
                        Text(lh("common.reset"))
                    }
                    .buttonStyle(MicroApps.MicroAppActionButtonStyle(tint: .secondary, isPrimary: false))
                }
            }
            .onReceive(timer) { _ in
                guard model.isRunning else { return }
                model.elapsed = Date().timeIntervalSince(model.startDate)
            }
        }
    }
}
