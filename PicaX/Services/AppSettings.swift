import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let hasConfirmedAdultAge = "picax.hasConfirmedAdultAge"
        static let hasCompletedOnboarding = "picax.hasCompletedOnboarding"
        static let hasAcceptedTerms = "picax.hasAcceptedTerms"
        static let hasAcceptedDisclaimer = "picax.hasAcceptedDisclaimer"
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

    @Published var hasAcceptedDisclaimer: Bool {
        didSet {
            defaults.set(hasAcceptedDisclaimer, forKey: Key.hasAcceptedDisclaimer)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasConfirmedAdultAge = defaults.bool(forKey: Key.hasConfirmedAdultAge)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedTerms = defaults.bool(forKey: Key.hasAcceptedTerms)
        hasAcceptedDisclaimer = defaults.bool(forKey: Key.hasAcceptedDisclaimer)
    }

    func confirmAdultAge() {
        hasConfirmedAdultAge = true
    }

    func acceptTerms() {
        hasAcceptedTerms = true
    }

    func acceptDisclaimerAndCompleteOnboarding() {
        hasCompletedOnboarding = true
        hasAcceptedDisclaimer = true
    }

    func reloadFromDefaults() {
        hasConfirmedAdultAge = defaults.bool(forKey: Key.hasConfirmedAdultAge)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedTerms = defaults.bool(forKey: Key.hasAcceptedTerms)
        hasAcceptedDisclaimer = defaults.bool(forKey: Key.hasAcceptedDisclaimer)
    }
}
