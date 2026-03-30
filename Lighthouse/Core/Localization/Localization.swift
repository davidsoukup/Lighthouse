import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case cs

    static let storageKey = "settings.appLanguage"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .system: return Locale.current.identifier
        case .en: return "en"
        case .cs: return "cs"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    var title: String {
        switch self {
        case .system: return L10n.tr("language.system")
        case .en: return L10n.tr("language.english")
        case .cs: return L10n.tr("language.czech")
        }
    }
}

enum L10n {
    static func currentLanguage() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.en.rawValue
        return AppLanguage(rawValue: raw) ?? .en
    }

    static func tr(_ key: String) -> String {
        let language = currentLanguage()
        let bundle = localizedBundle(for: language)
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: currentLanguage().locale, arguments: args)
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle {
        switch language {
        case .system:
            return Bundle.main
        case .en, .cs:
            guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                return Bundle.main
            }
            return bundle
        }
    }
}

/// Lightweight helper for localized string lookup used across views and runtime messages.
func lh(_ key: String) -> String {
    L10n.tr(key)
}
