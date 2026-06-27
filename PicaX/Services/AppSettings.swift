import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let hasCompletedOnboarding = "picax.hasCompletedOnboarding"
        static let hasAcceptedTerms = "picax.hasAcceptedTerms"
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        }
    }

    @Published var hasAcceptedTerms: Bool {
        didSet {
            defaults.set(hasAcceptedTerms, forKey: Key.hasAcceptedTerms)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedTerms = defaults.bool(forKey: Key.hasAcceptedTerms)
    }

    func completeOnboarding() {
        hasAcceptedTerms = true
        hasCompletedOnboarding = true
    }

    func reloadFromDefaults() {
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedTerms = defaults.bool(forKey: Key.hasAcceptedTerms)
    }
}
