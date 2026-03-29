import Foundation
import AppKit

enum SearchResultItem: Identifiable, Hashable {
    case app(name: String, path: String)
    case file(name: String, path: String)
    case microApp(key: String, desc: String, symbol: String)
    case web(query: String)

    /// Stable identity used by row selection + scroll targeting.
    var id: String {
        switch self {
        case .app(_, let p):        "a:\(p)"
        case .file(_, let p):       "f:\(p)"
        case .microApp(let k, _, _): "m:\(k)"
        case .web(let q):           "w:\(q)"
        }
    }

    /// Primary text rendered in results list.
    var displayName: String {
        switch self {
        case .app(let n, _), .file(let n, _): n
        case .microApp(let k, _, _):          "/\(k)"
        case .web:                            lh("search.result.web")
        }
    }

    /// Secondary text rendered under primary result label.
    var subtitle: String {
        switch self {
        case .app(_, let p):
            let dir = URL(fileURLWithPath: p).deletingLastPathComponent().lastPathComponent
            return dir == "Applications" ? "Applications" : dir == "Utilities" ? "Utilities" : dir
        case .file(_, let p):
            return URL(fileURLWithPath: p).deletingLastPathComponent().path
                .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        case .microApp(_, let d, _): return d
        case .web(let q):           return q
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
