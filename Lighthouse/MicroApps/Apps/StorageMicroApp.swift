import SwiftUI

extension MicroApps {
    /// Storage micro app card showing used/free/total disk capacity.
    @ViewBuilder
    static func storage() -> some View {
        let fm = FileManager.default

        if
            let attrs = try? fm.attributesOfFileSystem(forPath: "/"),
            let total = attrs[.systemSize] as? Int64,
            let free = attrs[.systemFreeSize] as? Int64
        {
            let used = total - free
            let pct = Int(Double(used) / Double(total) * 100)
            let barTint: Color = pct >= 90 ? .red : pct >= 75 ? .orange : .blue

            card(title: lh("microapp.storage.title"), subtitle: "\(pct)% \(lh("microapp.storage.used"))", icon: "internaldrive.fill", tint: .blue) {
                ProgressView(value: Double(pct), total: 100)
                    .progressViewStyle(.linear)
                    .tint(barTint)

                HStack(spacing: 20) {
                    infoLabel(lh("microapp.memory.used"), fmt(used))
                    infoLabel(lh("microapp.memory.free"), fmt(free))
                    infoLabel(lh("microapp.memory.total"), fmt(total))
                }
                .padding(.top, 2)
            }
        }
    }
}
