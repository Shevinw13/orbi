import AuthenticationServices
import Foundation

// MARK: - Auth State

/// Observable auth state shared across the app.
/// Requirements: 11.1, 11.2, 11.3
@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var userId: String?
    @Published var displayName: String?
    @Published var username: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Auto-Login

    /// Check for existing tokens on launch and restore session.
    func restoreSession() {
        guard KeychainHelper.read(.accessToken) != nil else {
            isAuthenticated = false
            return
        }
        isAuthenticated = true
    }

    // MARK: - Apple Sign-In (Req 11.1)

    /// Process the result from `ASAuthorizationController`.
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Unable to retrieve Apple credentials."
                return
            }

            let fullName: String? = {
                let components = credential.fullName
                let parts = [components?.givenName, components?.familyName].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()

            let body = AppleSignInRequest(identityToken: identityToken, name: fullName)
            await authenticate(path: "/auth/apple", body: body)

        case .failure(let error):
            // User cancellation is not an error worth surfacing
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Google Sign-In (Req 11.2) — Placeholder

    /// Call this with the Google ID token once the GoogleSignIn SDK is integrated.
    func handleGoogleSignIn(idToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = GoogleSignInRequest(idToken: idToken)
        await authenticate(path: "/auth/google", body: body)
    }

    // MARK: - Email/Password Auth

    func register(email: String?, password: String, name: String?, username: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = EmailAuthRequest(email: email, username: username, password: password, name: name)
        await authenticate(path: "/auth/register", body: body)
    }

    func login(email: String?, password: String, username: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body = EmailAuthRequest(email: email, username: username, password: password, name: nil)
        await authenticate(path: "/auth/login", body: body)
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainHelper.deleteAll()
        isAuthenticated = false
        userId = nil
        displayName = nil
        username = nil
    }

    func setUsername(_ newUsername: String) {
        username = newUsername
    }

    // MARK: - Private Helpers

    /// Send credentials to the backend, persist tokens on success.
    private func authenticate(path: String, body: some Encodable) async {
        do {
            let response: AuthResponse = try await APIClient.shared.request(
                .post,
                path: path,
                body: body,
                requiresAuth: false
            )

            try KeychainHelper.save(response.accessToken, for: .accessToken)
            try KeychainHelper.save(response.refreshToken, for: .refreshToken)

            userId = response.userId
            displayName = response.name
            username = response.username
            isAuthenticated = true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Sign-in failed. Please try again."
        }
    }
}
