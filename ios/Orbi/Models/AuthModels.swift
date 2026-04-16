import Foundation

// MARK: - Auth Request Models

/// Apple Sign-In request body matching backend `POST /auth/apple`.
/// Requirements: 11.1
struct AppleSignInRequest: Encodable {
    let identityToken: String
    let name: String?
}

/// Google Sign-In request body matching backend `POST /auth/google`.
/// Requirements: 11.2
struct GoogleSignInRequest: Encodable {
    let idToken: String
}

/// Token refresh request body matching backend `POST /auth/refresh`.
/// Requirements: 11.5
struct RefreshRequest: Encodable {
    let refreshToken: String
}

/// Email/username register/login request body.
struct EmailAuthRequest: Encodable {
    let email: String?
    let username: String?
    let password: String
    let name: String?
}

// MARK: - Auth Response Model

/// Successful authentication response from the backend.
/// Requirements: 11.3
struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let userId: String
    let name: String?
    let username: String?
}
