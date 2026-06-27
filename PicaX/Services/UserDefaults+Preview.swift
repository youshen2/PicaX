import Foundation

extension UserDefaults {
    static var preview: UserDefaults {
        UserDefaults(suiteName: "picax.preview") ?? .standard
    }
}
