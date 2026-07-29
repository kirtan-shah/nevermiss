import Foundation
import AuthenticationServices
import CommonCrypto

// MARK: - Type Definition

@Observable
@MainActor
final class GoogleAuthService: NSObject {

    // MARK: - Static Properties

    static let shared = GoogleAuthService()

    // MARK: - Properties

    private(set) var connectionState: ConnectionState = .checking
    var isAuthenticating = false
    var authError: AuthError?

    var isAuthenticated: Bool {
        connectionState == .connected
    }

    var needsReauth: Bool {
        connectionState == .reconnectRequired
    }

    var isAuthenticationStatusUnavailable: Bool {
        connectionState == .temporarilyUnavailable
    }

    @ObservationIgnored private let tokenManager = TokenManager.shared
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var authenticationCheckTask: Task<Void, Never>?

    // MARK: - Initialization

    override init() {
        super.init()
        Task {
            await checkAuthenticationStatus()
        }
    }

    // MARK: - Actions/Methods

    func signIn() async throws {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        authError = nil

        defer { isAuthenticating = false }

        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString

        // Build authorization URL
        let authURL = buildAuthorizationURL(codeChallenge: codeChallenge, state: state)

        // Present authentication session
        let callbackURL = try await presentAuthSession(url: authURL)

        // Extract authorization code
        guard let code = extractAuthorizationCode(from: callbackURL, expectedState: state) else {
            throw AuthError.noAuthorizationCode
        }

        do {
            try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
        } catch let error as AuthError {
            if case .missingRequiredScopes = error {
                await handleTokenExpired()
            }
            throw error
        }

        do {
            try await fetchUserInfo()
        } catch let error as TokenManager.TokenError where error.requiresReauthentication {
            await handleTokenExpired()
            throw error
        } catch let error as AuthError where error.requiresReauthentication {
            await handleTokenExpired()
            throw error
        } catch {
            // The token exchange succeeded. A network/server/profile decoding failure
            // does not prove the credentials are invalid, so keep the account usable
            // and let calendar sync retry instead of producing a false disconnect.
            authError = error as? AuthError
        }

        connectionState = .connected
        SettingsManager.shared.suppressReauthPopup = false
    }

    func signInForUserAction() async -> String? {
        do {
            try await signIn()
            return nil
        } catch let error as AuthError {
            if case .userCancelled = error {
                return nil
            }
            return error.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await tokenManager.clearTokens()
        } catch {
            print("Error clearing tokens: \(error)")
        }

        SettingsManager.shared.disconnectGoogleAccount()
        connectionState = .disconnected
    }

    func checkAuthenticationStatus() async {
        if let authenticationCheckTask {
            await authenticationCheckTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAuthenticationStatusCheck()
        }
        authenticationCheckTask = task
        await task.value
        authenticationCheckTask = nil
    }

    func handleTokenExpired() async {
        try? await tokenManager.clearTokens()

        connectionState = SettingsManager.shared.googleAccount == nil
            ? .disconnected
            : .reconnectRequired

        if needsReauth && !SettingsManager.shared.suppressReauthPopup {
            NotificationCenter.default.post(name: .googleAuthExpired, object: nil)
        }
    }

    // MARK: - Private Helpers

    private func performAuthenticationStatusCheck() async {
        switch await tokenManager.credentialAvailability() {
        case .missing:
            connectionState = SettingsManager.shared.googleAccount == nil
                ? .disconnected
                : .reconnectRequired
            return

        case .unavailable(_):
            // A keychain read failure proves neither that credentials work nor that
            // they were revoked. Keep this distinct from Connected and Reconnect.
            connectionState = .temporarilyUnavailable
            return

        case .available:
            break
        }

        do {
            try await fetchUserInfo()
            connectionState = .connected
        } catch let error as TokenManager.TokenError {
            if error.requiresReauthentication {
                await handleTokenExpired()
            } else {
                connectionState = .connected
            }
        } catch let error as AuthError {
            if error.requiresReauthentication {
                await handleTokenExpired()
            } else {
                connectionState = .connected
            }
        } catch {
            // Decoding and other unexpected probe failures are indeterminate. The
            // locally stored credentials still exist and may work on the next sync.
            connectionState = .connected
        }
    }

    private func buildAuthorizationURL(codeChallenge: String, state: String) -> URL {
        var components = URLComponents(string: GoogleConfig.authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleConfig.scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleConfig.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.authSession = nil

                if let error = error {
                    if let sessionError = error as? ASWebAuthenticationSessionError,
                       sessionError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: AuthError.sessionError(error))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.start()
        }
    }

    private func extractAuthorizationCode(from url: URL, expectedState: String) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        // Verify state
        guard let state = queryItems.first(where: { $0.name == "state" })?.value,
              state == expectedState else {
            return nil
        }

        // Get authorization code
        return queryItems.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws {
        var request = URLRequest(url: URL(string: GoogleConfig.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": GoogleConfig.clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleConfig.redirectURI
        ].map { key, value in
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(escapedValue)"
        }.joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(errorMessage)
        }

        let tokenResponse = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        try validateGrantedScopes(tokenResponse.scope)

        try await tokenManager.storeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
    }

    private func fetchUserInfo(isRetry: Bool = false) async throws {
        let accessToken = try await tokenManager.getValidAccessToken()

        var request = URLRequest(url: URL(string: GoogleConfig.userInfoEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidUserInfoResponse
        }

        if httpResponse.statusCode == 401 {
            if !isRetry {
                // The access token can be rejected before its stored expiry while
                // the refresh token is still valid. Refresh once before declaring
                // the account disconnected to avoid a false Reconnect state.
                _ = try await tokenManager.refreshAccessToken()
                return try await fetchUserInfo(isRetry: true)
            }
            throw AuthError.userInfoUnauthorized
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.userInfoFetchFailed(errorMessage)
        }

        let userInfo: GoogleUserInfo
        do {
            userInfo = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
        } catch {
            throw AuthError.invalidUserInfoResponse
        }

        await MainActor.run {
            let account = GoogleAccount(
                email: userInfo.email,
                displayName: userInfo.name,
                profileImageURL: userInfo.picture.flatMap { URL(string: $0) }
            )
            SettingsManager.shared.googleAccount = account
        }
    }

    private func validateGrantedScopes(_ grantedScopeString: String?) throws {
        // OAuth permits omitting `scope` when it is identical to the requested
        // scope. If Google supplies it, validate it; otherwise the subsequent API
        // probe is the authoritative permission check.
        guard let grantedScopeString else { return }

        let grantedScopes = Set(grantedScopeString.split(separator: " ").map(String.init))
        let requiredScopes = [GoogleConfig.calendarScope]
        let missingScopes = requiredScopes.filter { !grantedScopes.contains($0) }

        if !missingScopes.isEmpty {
            throw AuthError.missingRequiredScopes(missingScopes)
        }
    }

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64URLEncodedString()
    }
}

// MARK: - Extensions

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first { $0.isKeyWindow } ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Supporting Types

extension GoogleAuthService {
    enum ConnectionState: Equatable {
        case checking
        case connected
        case disconnected
        case reconnectRequired
        case temporarilyUnavailable
    }

    enum AuthError: Error, LocalizedError {
        case userCancelled
        case sessionError(Error)
        case invalidCallback
        case noAuthorizationCode
        case tokenExchangeFailed(String)
        case networkError(Error)
        case invalidState
        case missingRequiredScopes([String])
        case invalidUserInfoResponse
        case userInfoUnauthorized
        case userInfoFetchFailed(String)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                return "Sign in was cancelled"
            case .sessionError(let error):
                return "Authentication failed: \(error.localizedDescription)"
            case .invalidCallback:
                return "Invalid callback from Google"
            case .noAuthorizationCode:
                return "No authorization code received"
            case .tokenExchangeFailed(let message):
                return "Token exchange failed: \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidState:
                return "Invalid authentication state"
            case .missingRequiredScopes(let scopes):
                return "Required Google permissions were not granted: \(scopes.joined(separator: ", "))"
            case .invalidUserInfoResponse:
                return "Invalid response from Google user info endpoint"
            case .userInfoUnauthorized:
                return "Google account access was revoked"
            case .userInfoFetchFailed(let message):
                return "Failed to fetch Google account info: \(message)"
            }
        }

        nonisolated var requiresReauthentication: Bool {
            switch self {
            case .userInfoUnauthorized, .missingRequiredScopes:
                return true
            case .userCancelled, .sessionError, .invalidCallback,
                 .noAuthorizationCode, .tokenExchangeFailed, .networkError,
                 .invalidState, .invalidUserInfoResponse, .userInfoFetchFailed:
                return false
            }
        }
    }
}

private struct TokenExchangeResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

private struct GoogleUserInfo: Codable {
    let id: String
    let email: String
    let name: String?
    let picture: String?
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
