import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let hasConfirmedAdultAge = "picax.hasConfirmedAdultAge"
        static let hasCompletedOnboarding = "picax.hasCompletedOnboarding"
        static let hasAcceptedTerms = "picax.hasAcceptedTerms"
    }

    @Published var hasConfirmedAdultAge: Bool {
        didSet {
            defaults.set(hasConfirmedAdultAge, forKey: Key.hasConfirmedAdultAge)
        }
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
        hasConfirmedAdultAge = defaults.bool(forKey: Key.hasConfirmedAdultAge)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedTerms = defaults.bool(forKey: Key.hasAcceptedTerms)
    }

    func confirmAdultAge() {
        hasConfirmedAdultAge = true
    }

    func completeOnboarding() {
        hasAcceptedTerms = true
        hasCompletedOnboarding = true
    }

    func reloadFromDefaults() {
        hasConfirmedAdultAge = defaults.bool(forKey: Key.hasConfirmedAdultAge)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedTerms = defaults.bool(forKey: Key.hasAcceptedTerms)
    }
}
