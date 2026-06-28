import Foundation

enum L10n {
    static func string(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
        String(localized: key, locale: AppLanguageMode.selectedLocale, comment: comment)
    }
}
