import Foundation
import Combine

/// Owns the user's session token.
///
/// V1 uses a local stub token because the Apple Developer free tier doesn't
/// support Sign in with Apple. The Worker's `?dev=1` mode (already enabled in
/// `NyamAPI.appendDevFlag`) accepts any token, so the stub is sufficient for
/// the class demo. The architecture is left ready for SIWA — swap the stub
/// for `SignInWithAppleButton` once a paid developer account is available.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var identityToken: String?

    var isSignedIn: Bool { identityToken != nil }

    init() {
        identityToken = Keychain.load()
    }

    /// V1 stub. Stores a placeholder token in Keychain so the rest of the app
    /// behaves identically to a real signed-in state.
    func signInAsGuest() {
        let stub = "stub-token-\(UUID().uuidString)"
        Keychain.save(stub)
        identityToken = stub
    }

    func signOut() {
        Keychain.clear()
        identityToken = nil
    }
}
