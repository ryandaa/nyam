import Foundation
import AuthenticationServices
import Combine

/// Owns the user's Apple identity token. Persists it to Keychain.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var identityToken: String?
    @Published private(set) var userIdentifier: String?

    var isSignedIn: Bool { identityToken != nil }

    init() {
        identityToken = Keychain.load()
    }

    /// Call from `SignInWithAppleButton`'s `onCompletion`.
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                return
            }
            Keychain.save(token)
            identityToken = token
            userIdentifier = credential.user
        case let .failure(error):
            #if DEBUG
            print("Sign in with Apple failed: \(error.localizedDescription)")
            #endif
        }
    }

    func signOut() {
        Keychain.clear()
        identityToken = nil
        userIdentifier = nil
    }
}
