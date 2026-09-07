import Foundation

/// Assembles the real (Keychain + URLSession) dependencies used by the
/// running app.
///
/// This is intentionally a small factory, not a general DI container, per
/// the brief's guidance against introducing heavyweight frameworks.
/// Tests bypass this entirely and construct view models directly with
/// fakes.
@MainActor
struct AppDependencies {
    let credentialStore: CredentialStore
    let veniceChecker: ConnectionChecking
    let openRouterChecker: ConnectionChecking

    static func live() -> AppDependencies {
        let credentialStore = KeychainCredentialStore()
        let veniceChecker = VeniceConnectionChecker(
            httpClient: URLSessionHTTPClient(allowedHost: AIService.venice.apiHost)
        )
        let openRouterChecker = OpenRouterConnectionChecker(
            httpClient: URLSessionHTTPClient(allowedHost: AIService.openRouter.apiHost)
        )
        return AppDependencies(
            credentialStore: credentialStore,
            veniceChecker: veniceChecker,
            openRouterChecker: openRouterChecker
        )
    }

    func makeAccountSettingsViewModel() -> AccountSettingsViewModel {
        AccountSettingsViewModel(
            credentialStore: credentialStore,
            checkers: [
                .venice: veniceChecker,
                .openRouter: openRouterChecker
            ]
        )
    }
}
