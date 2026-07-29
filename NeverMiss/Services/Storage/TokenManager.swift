import Foundation

// MARK: - Type Definition

actor TokenManager {

    // MARK: - Static Properties

    static let shared = TokenManager()

    // MARK: - Properties

    private let keychainService = KeychainService.shared

    /// Buffer time before expiry to trigger refresh (5 minutes)
    private let refreshBuffer: TimeInterval = 300

    // MARK: - Computed Properties

    var isAuthenticated: Bool {
        get async {
            if case .available = await credentialAvailability() {
                return true
            }
            return false
        }
    }

    // MARK: - Actions/Methods

    func storeTokens(accessToken: String, refreshToken: String?, expiresIn: Int) async throws {
        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        try await keychainService.saveGoogleTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiryDate: expiryDate
        )
    }

    /// Get a valid access token, refreshing if necessary
    func getValidAccessToken() async throws -> String {
        let expiry = try await keychainService.getGoogleTokenExpiry()
        let accessToken = try await keychainService.getGoogleAccessToken()

        if let expiry, expiry > Date(), let accessToken {
            if expiry.timeIntervalSinceNow > refreshBuffer {
                return accessToken
            }

            // An access-only credential is still usable until its actual expiry.
            // Requiring reconnect merely because it entered the proactive refresh
            // window would produce a false disconnected state up to five minutes early.
            if try await keychainService.getGoogleRefreshToken() == nil {
                return accessToken
            }
        }

        // Token expired or about to expire - refresh it
        return try await refreshAccessToken()
    }

    func clearTokens() async throws {
        try await keychainService.clearGoogleTokens()
    }

    /// Reports whether the keychain contains credentials that can be used now or
    /// refreshed later. A valid access token without a refresh token remains usable
    /// until it expires, so checking only for a refresh token causes false negatives.
    func credentialAvailability() async -> CredentialAvailability {
        do {
            if try await keychainService.getGoogleRefreshToken() != nil {
                return .available
            }

            if try await keychainService.getGoogleAccessToken() != nil,
               let expiry = try await keychainService.getGoogleTokenExpiry(),
               expiry > Date() {
                return .available
            }

            return .missing
        } catch {
            return .unavailable(error)
        }
    }

    // MARK: - Token Refresh

    @discardableResult
    func refreshAccessToken() async throws -> String {
        guard let refreshToken = try await keychainService.getGoogleRefreshToken() else {
            throw TokenError.noRefreshToken
        }

        var request = URLRequest(url: URL(string: GoogleConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": GoogleConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ].map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TokenError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenError.refreshFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let failure = Self.classifyRefreshFailure(
                statusCode: httpResponse.statusCode,
                data: data
            )

            if failure.requiresReauthentication {
                // Clearing is best-effort. The caller still needs the definitive
                // tokenExpired result so it can enter the Reconnect state.
                try? await keychainService.clearGoogleTokens()
            }

            throw failure
        }

        // Parse response
        let tokenResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        // Store new tokens
        try await storeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken, // May be nil
            expiresIn: tokenResponse.expiresIn
        )

        return tokenResponse.accessToken
    }

    /// OAuth token endpoints use HTTP 400 for both revoked credentials and request/
    /// client configuration errors. Only `invalid_grant` proves that the saved refresh
    /// token can no longer be used and that the user must reconnect.
    nonisolated static func classifyRefreshFailure(statusCode: Int, data: Data) -> TokenError {
        let response = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)

        if response?.error == "invalid_grant" {
            return .tokenExpired
        }

        let detail = [response?.error, response?.errorDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
        let suffix = detail.isEmpty ? "" : " (\(detail))"
        return .refreshFailed("HTTP \(statusCode)\(suffix)")
    }
}

// MARK: - Supporting Types

extension TokenManager {
    enum CredentialAvailability {
        case available
        case missing
        case unavailable(Error)
    }

    enum TokenError: Error, LocalizedError {
        case noAccessToken
        case noRefreshToken
        case refreshFailed(String)
        case tokenExpired
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noAccessToken:
                return "No access token available"
            case .noRefreshToken:
                return "No refresh token available. Please sign in again."
            case .refreshFailed(let message):
                return "Token refresh failed: \(message)"
            case .tokenExpired:
                return "Token has expired. Please sign in again."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }

        nonisolated var requiresReauthentication: Bool {
            switch self {
            case .noAccessToken, .noRefreshToken, .tokenExpired:
                return true
            case .refreshFailed, .networkError:
                return false
            }
        }
    }
}

nonisolated private struct TokenRefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

nonisolated private struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
