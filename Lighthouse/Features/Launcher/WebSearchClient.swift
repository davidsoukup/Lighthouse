import Foundation

enum WebSearchClient {
    static func search(query: String) async -> [WebSearchResult] {
        guard
            let key = BraveAPIKeyStore.load() ?? ProcessInfo.processInfo.environment["BRAVE_API_KEY"],
            !key.isEmpty
        else {
            return [WebSearchResult(
                title: "Web search not configured",
                snippet: "Open Settings and add your Brave API key.",
                link: ""
            )]
        }

        var comps = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
        comps?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "3"),
            URLQueryItem(name: "country", value: "us"),
            URLQueryItem(name: "search_lang", value: "en")
        ]
        guard let url = comps?.url else { return [] }

        do {
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            req.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                return [WebSearchResult(
                    title: "Web search error",
                    snippet: msg,
                    link: ""
                )]
            }
            if let results = parseBraveResults(data), !results.isEmpty {
                return results
            }
            let msg = String(data: data, encoding: .utf8) ?? "No results."
            return [WebSearchResult(
                title: "Web search error",
                snippet: msg,
                link: ""
            )]
        } catch {
            return [WebSearchResult(
                title: "Web search error",
                snippet: error.localizedDescription,
                link: ""
            )]
        }
    }
}

private func parseBraveResults(_ data: Data) -> [WebSearchResult]? {
    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let web = json["web"] as? [String: Any],
        let results = web["results"] as? [[String: Any]]
    else { return nil }

    return results.compactMap { item in
        let title = (item["title"] as? String) ?? ""
        let link = (item["url"] as? String) ?? ""
        let snippet = (item["description"] as? String) ?? ""
        if title.isEmpty && link.isEmpty && snippet.isEmpty { return nil }
        return WebSearchResult(title: title, snippet: snippet, link: link)
    }
}
