import SwiftUI
import AppKit

struct WebResultsCard: View {
    let query: String
    let results: [WebSearchResult]

    @State private var hoveredLink: String? = nil

    /// Web search response card shown in chat history.
    var body: some View {
        MicroApps.card(title: lh("web.title"), subtitle: query, icon: "globe", tint: Color(red: 0.2, green: 0.5, blue: 1.0)) {
            if results.isEmpty {
                Text(lh("web.no_results"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if results.count == 1, results[0].link.isEmpty {
                Text(results[0].snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, item in
                        resultRow(item)
                    }
                }
            }
        }
    }

    /// One clickable result row with favicon, title, snippet, and host.
    @ViewBuilder
    private func resultRow(_ item: WebSearchResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            favicon(for: item.link)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(item.snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(displayHost(item.link))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hoveredLink == item.link ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { openLink(item.link) }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredLink = hovering ? item.link : (hoveredLink == item.link ? nil : hoveredLink)
            }
        }
    }

    /// Lightweight favicon resolver using Google's favicon endpoint.
    @ViewBuilder
    private func favicon(for link: String) -> some View {
        if let host = URL(string: link)?.host,
           let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
            AsyncImage(url: url) { image in
                image.resizable()
            } placeholder: {
                Color.primary.opacity(0.08)
            }
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Color.primary.opacity(0.08)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    /// Extracts host for compact URL display.
    private func displayHost(_ link: String) -> String {
        guard let url = URL(string: link), let host = url.host else { return link }
        return host
    }

    /// Opens result link in default browser.
    private func openLink(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}
