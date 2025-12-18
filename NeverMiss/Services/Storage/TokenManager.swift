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
            await keychainService.hasGoogleTokens()
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
        // Check if current token is still valid
        if let expiry = try await keychainService.getGoogleTokenExpiry(),
           expiry.timeIntervalSinceNow > refreshBuffer,
           let accessToken = try await keychainService.getGoogleAccessToken() {
            return accessToken
        }

        // Token expired or about to expire - refresh it
        return try await refreshAccessToken()
    }

    func clearTokens() async throws {
        try await keychainService.clearGoogleTokens()
    }

    // MARK: - Private Helpers

    private func refreshAccessToken() async throws -> String {
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

        // Handle error responses
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            // Refresh token is invalid - user needs to re-authenticate
            try await keychainService.clearGoogleTokens()
            throw TokenError.tokenExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw TokenError.refreshFailed("HTTP \(httpResponse.statusCode)")
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
}

// MARK: - Supporting Types

extension TokenManager {
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
    }
}

private struct TokenRefreshResponse: Codable {
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
