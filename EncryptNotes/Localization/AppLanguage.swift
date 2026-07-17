import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case german = "de"
    case french = "fr"
    case portuguese = "pt"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .german: return "German"
        case .french: return "French"
        case .portuguese: return "Portuguese"
        }
    }

    var resolvedIdentifier: String {
        switch self {
        case .system:
            return Self.supportedIdentifier(for: Locale.preferredLanguages.first) ?? AppLanguage.english.rawValue
        default:
            return rawValue
        }
    }

    var locale: Locale {
        Locale(identifier: resolvedIdentifier)
    }

    static func supportedIdentifier(for preferredLanguage: String?) -> String? {
        guard let preferredLanguage else { return nil }
        let normalized = preferredLanguage.replacingOccurrences(of: "_", with: "-").lowercased()

        if normalized.hasPrefix("zh") {
            if normalized.contains("hant") || normalized.contains("-tw") || normalized.contains("-hk") || normalized.contains("-mo") {
                return AppLanguage.traditionalChinese.rawValue
            }
            return AppLanguage.simplifiedChinese.rawValue
        }

        for language in [english, japanese, korean, spanish, german, french, portuguese] {
            if normalized == language.rawValue.lowercased() || normalized.hasPrefix(language.rawValue.lowercased() + "-") {
                return language.rawValue
            }
        }
        return nil
    }
}

struct AppLocalizedRoot<Content: View>: View {
    @ObservedObject private var settings = SettingsStore.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, settings.appLanguage.locale)
            .id(settings.appLanguage.resolvedIdentifier)
    }
}

enum L10n {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let language = SettingsStore.shared.appLanguage.resolvedIdentifier
        let localized = localizedValue(forKey: key, language: language)
            ?? localizedValue(forKey: key, language: AppLanguage.english.rawValue)
            ?? key
        guard !arguments.isEmpty else { return localized }
        return String(format: localized, locale: SettingsStore.shared.appLanguage.locale, arguments: arguments)
    }

    private static func localizedValue(forKey key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}
