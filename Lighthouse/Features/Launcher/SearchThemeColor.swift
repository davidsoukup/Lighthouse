import SwiftUI

enum SearchThemeColor: String, CaseIterable {
    case charcoal
    case slate
    case cobalt
    case indigo
    case emerald
    case mint
    case amber
    case orange
    case rose
    case violet

    var title: String {
        switch self {
        case .charcoal: return lh("theme.charcoal")
        case .slate: return lh("theme.slate")
        case .cobalt: return lh("theme.cobalt")
        case .indigo: return lh("theme.indigo")
        case .emerald: return lh("theme.emerald")
        case .mint: return lh("theme.mint")
        case .amber: return lh("theme.amber")
        case .orange: return lh("theme.orange")
        case .rose: return lh("theme.rose")
        case .violet: return lh("theme.violet")
        }
    }

    var color: Color {
        switch self {
        case .charcoal: return Color(red: 0.08, green: 0.08, blue: 0.10)
        case .slate: return Color(red: 0.14, green: 0.16, blue: 0.20)
        case .cobalt: return Color(red: 0.09, green: 0.19, blue: 0.35)
        case .indigo: return Color(red: 0.15, green: 0.16, blue: 0.34)
        case .emerald: return Color(red: 0.06, green: 0.23, blue: 0.19)
        case .mint: return Color(red: 0.08, green: 0.28, blue: 0.24)
        case .amber: return Color(red: 0.30, green: 0.20, blue: 0.07)
        case .orange: return Color(red: 0.35, green: 0.17, blue: 0.04)
        case .rose: return Color(red: 0.29, green: 0.13, blue: 0.18)
        case .violet: return Color(red: 0.24, green: 0.14, blue: 0.31)
        }
    }

    var overlayOpacity: Double {
        switch self {
        case .charcoal: return 0.48
        case .slate: return 0.44
        case .cobalt, .indigo, .emerald, .mint, .amber, .orange, .rose, .violet:
            return 0.38
        }
    }

    var accentColor: Color {
        switch self {
        case .charcoal: return Color(red: 0.34, green: 0.44, blue: 0.70)
        case .slate: return Color(red: 0.44, green: 0.57, blue: 0.86)
        case .cobalt: return Color(red: 0.30, green: 0.58, blue: 1.00)
        case .indigo: return Color(red: 0.49, green: 0.55, blue: 0.95)
        case .emerald: return Color(red: 0.25, green: 0.84, blue: 0.66)
        case .mint: return Color(red: 0.36, green: 0.90, blue: 0.82)
        case .amber: return Color(red: 1.00, green: 0.74, blue: 0.34)
        case .orange: return Color(red: 1.00, green: 0.58, blue: 0.30)
        case .rose: return Color(red: 1.00, green: 0.49, blue: 0.66)
        case .violet: return Color(red: 0.78, green: 0.52, blue: 1.00)
        }
    }
}
