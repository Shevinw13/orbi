import Foundation
import Combine

// MARK: - Error Types

/// Structured API errors with user-friendly messages.
/// Requirements: 14.3, 14.4
enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(statusCode: Int, message: String)
    case networkUnavailable
    case decodingFailed(Error)
    case tokenRefreshFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden:
            return "You don't have permission to access this resource."
        case .notFound:
            return "The requested resource was not found."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError(_, let message):
            return message
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .decodingFailed:
            return "We received an unexpected response. Please try again."
        case .tokenRefreshFailed:
            return "Unable to refresh your session. Please sign in again."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

/// Backend error response shape matching `ErrorResponse` from the API.
private struct ServerError: Decodable {
    let detail: String?
    let error: String?
    let message: String?
}

// MARK: - API Client

/// Main API client using URLSession async/await.
/// Handles Bearer token injection, automatic 401 refresh-and-retry.
/// Requirements: 11.5, 11.6, 14.3, 14.4
actor APIClient {

    static let shared = APIClient()

    // MARK: - Configuration

    /// Base URL for the backend API.
    #if DEBUG
    #if targetEnvironment(simulator)
    private let baseURL = URL(string: "http://localhost:8000")!
    #else
    private let baseURL = URL(string: "https://orbi-89zi.onrender.com")!
    #endif
    #else
    private let baseURL = URL(string: "https://orbi-89zi.onrender.com")!
    #endif

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Tracks whether a token refresh is already in-flight to avoid duplicate refreshes.
    private var isRefreshing = false

    /// Maximum number of automatic retries when network becomes available again.
    private let maxConnectivityRetries = 1

    /// Timeout in seconds to wait for connectivity restoration before giving up.
    private let connectivityWaitTimeout: TimeInterval = 30

    // MARK: - Init

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Public Request Methods

    /// Perform a request and decode the response into `T`.
    func request<T: Decodable>(
        _ method: HTTPMethod,
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        let data = try await performRequest(
            method, path: path, body: body,
            queryItems: queryItems, requiresAuth: requiresAuth,
            isRetry: false
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    /// Perform a request that returns no meaningful body (e.g. DELETE).
    func requestVoid(
        _ method: HTTPMethod,
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws {
        _ = try await performRequest(
            method, path: path, body: body,
            queryItems: queryItems, requiresAuth: requiresAuth,
            isRetry: false
        )
    }

    // MARK: - Core Request Logic

    private func performRequest(
        _ method: HTTPMethod,
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool,
        isRetry: Bool
    ) async throws -> Data {
        // Build URL
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        // Build URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Inject Bearer token
        if requiresAuth, let token = KeychainHelper.read(.accessToken) {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Execute
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet
            || urlError.code == .networkConnectionLost {
            // Requirement 14.3: Auto-retry when connectivity is restored
            if !isRetry {
                return try await waitForConnectivityAndRetry(
                    method, path: path, body: body,
                    queryItems: queryItems, requiresAuth: requiresAuth
                )
            }
            throw APIError.networkUnavailable
        } catch {
            throw APIError.unknown(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(
                NSError(domain: "APIClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            )
        }

        // Handle status codes
        switch httpResponse.statusCode {
        case 200...299:
            return data

        case 401:
            // Auto-refresh on 401 if this isn't already a retry
            if requiresAuth, !isRetry {
                try await refreshTokens()
                return try await performRequest(
                    method, path: path, body: body,
                    queryItems: queryItems, requiresAuth: requiresAuth,
                    isRetry: true
                )
            }
            throw APIError.unauthorized

        case 403:
            throw APIError.forbidden

        case 404:
            throw APIError.notFound

        case 429:
            throw APIError.rateLimited

        default:
            let message = parseServerMessage(from: data)
                ?? "Server error (\(httpResponse.statusCode)). Please try again."
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    // MARK: - Connectivity Retry

    /// Waits for network connectivity to be restored, then retries the request once.
    /// Requirements: 14.3
    private func waitForConnectivityAndRetry(
        _ method: HTTPMethod,
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool
    ) async throws -> Data {
        // Wait for the NetworkMonitor to signal connectivity restored, with a timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var cancellable: AnyCancellable?
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(connectivityWaitTimeout * 1_000_000_000))
                cancellable?.cancel()
                continuation.resume(throwing: APIError.networkUnavailable)
            }

            cancellable = NetworkMonitor.shared.connectivityRestored
                .first()
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    timeoutTask.cancel()
                    continuation.resume()
                }
        }

        // Retry the original request once
        return try await performRequest(
            method, path: path, body: body,
            queryItems: queryItems, requiresAuth: requiresAuth,
            isRetry: true
        )
    }

    // MARK: - Token Refresh

    /// Calls `/auth/refresh` with the stored refresh token, saves new tokens.
    /// Requirements: 11.5
    private func refreshTokens() async throws {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let refreshToken = KeychainHelper.read(.refreshToken) else {
            throw APIError.tokenRefreshFailed
        }

        struct RefreshBody: Encodable {
            let refreshToken: String
        }
        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String
        }

        let body = RefreshBody(refreshToken: refreshToken)
        let data = try await performRequest(
            .post, path: "/auth/refresh", body: body,
            requiresAuth: false, isRetry: true  // isRetry=true to prevent infinite loop
        )

        do {
            let tokens = try decoder.decode(RefreshResponse.self, from: data)
            try KeychainHelper.save(tokens.accessToken, for: .accessToken)
            try KeychainHelper.save(tokens.refreshToken, for: .refreshToken)
        } catch is KeychainError {
            throw APIError.tokenRefreshFailed
        } catch {
            throw APIError.tokenRefreshFailed
        }
    }

    // MARK: - Helpers

    private func parseServerMessage(from data: Data) -> String? {
        let serverError = try? decoder.decode(ServerError.self, from: data)
        return serverError?.message ?? serverError?.detail ?? serverError?.error
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
