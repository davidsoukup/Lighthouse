import SwiftUI

extension MicroApps {
    /// Memory micro app card with RAM usage and byte breakdown.
    struct MemoryCard: View {
        @State private var info: MemoryInfo? = nil
        @State private var didLoad = false

        var body: some View {
            MicroApps.card(title: lh("microapp.memory.title"), subtitle: lh("microapp.memory.subtitle"), icon: "memorychip", tint: .orange) {
                if let info {
                    ProgressView(value: Double(info.pct), total: 100)
                        .progressViewStyle(.linear)
                        .tint(info.pct >= 90 ? .red : info.pct >= 75 ? .red : .orange)
                    HStack(spacing: 12) {
                        MicroApps.infoLabel(lh("microapp.memory.used"), fmt(info.used))
                        MicroApps.infoLabel(lh("microapp.memory.free"), fmt(info.free))
                        MicroApps.infoLabel(lh("microapp.memory.total"), fmt(info.total))
                    }
                } else if didLoad {
                    MicroApps.kvRow(lh("microapp.status"), lh("common.na"))
                } else {
                    ProgressView().controlSize(.small).tint(.secondary)
                }
            }
            .task {
                info = await memoryInfo()
                didLoad = true
            }
        }
    }
}
