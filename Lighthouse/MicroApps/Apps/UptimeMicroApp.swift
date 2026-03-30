import SwiftUI

extension MicroApps {
    /// Uptime micro app card with elapsed runtime and load averages.
    struct UptimeCard: View {
        @State private var info: UptimeInfo? = nil
        @State private var didLoad = false

        var body: some View {
            MicroApps.card(title: lh("microapp.uptime.title"), subtitle: lh("microapp.uptime.subtitle"), icon: "clock", tint: .indigo) {
                if let info {
                    MicroApps.kvRow(lh("microapp.uptime.running"), info.up)
                    MicroApps.kvRow(lh("microapp.uptime.load"), info.load, monospaced: true)
                } else if didLoad {
                    MicroApps.kvRow(lh("microapp.status"), lh("common.na"))
                } else {
                    ProgressView().controlSize(.small).tint(.secondary)
                }
            }
            .task {
                info = await uptimeInfo()
                didLoad = true
            }
        }
    }
}
