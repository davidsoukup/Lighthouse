import SwiftUI
import AppKit

struct ResultRow: View {
    let item: SearchResultItem
    let isSelected: Bool
    @AppStorage("settings.searchThemeColor") private var searchThemeColorRaw: String = SearchThemeColor.charcoal.rawValue

    private var searchTheme: SearchThemeColor {
        SearchThemeColor(rawValue: searchThemeColorRaw) ?? .charcoal
    }

    /// Search result row used by app/file/micro app/web sections.
    var body: some View {
        HStack(spacing: 12) {
            rowIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isSelected { Text("↵").font(.system(size: 12)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? searchTheme.accentColor.opacity(0.18) : Color.clear))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// Icon renderer tailored by search result type.
    @ViewBuilder
    private var rowIcon: some View {
        switch item {
        case .app(_, let p), .file(_, let p):
            Image(nsImage: NSWorkspace.shared.icon(forFile: p))
                .resizable().frame(width: 32, height: 32)
        case .microApp(_, _, let sym):
            Image(systemName: sym)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(searchTheme.accentColor)
                .frame(width: 32, height: 32)
                .background(searchTheme.accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .web:
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
