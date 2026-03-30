import SwiftUI

extension MicroApps {
    /// CPU usage micro app card with user/system/idle meters.
    struct CpuCard: View {
        @State private var info: CpuInfo? = nil
        @State private var didLoad = false

        var body: some View {
            MicroApps.card(title: lh("microapp.cpu.title"), subtitle: lh("microapp.cpu.subtitle"), icon: "cpu", tint: .purple) {
                if let info {
                    MicroApps.meterRow(lh("microapp.cpu.user"), info.user, tint: .purple)
                    MicroApps.meterRow(lh("microapp.cpu.system"), info.sys, tint: .indigo)
                    MicroApps.meterRow(lh("microapp.cpu.idle"), info.idle, tint: .green)
                } else if didLoad {
                    MicroApps.kvRow(lh("microapp.status"), lh("common.na"))
                } else {
                    ProgressView().controlSize(.small).tint(.secondary)
                }
            }
            .task {
                info = await cpuInfo()
                didLoad = true
            }
        }
    }
}
