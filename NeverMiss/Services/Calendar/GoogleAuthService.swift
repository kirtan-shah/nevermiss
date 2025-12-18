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

    var isAuthenticated = false
    var isAuthenticating = false
    var authError: AuthError?

    @ObservationIgnored private let tokenManager = TokenManager.shared
    @ObservationIgnored private let keychainService = KeychainService.shared
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?

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

        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)

        // Fetch user info
        try await fetchUserInfo()

        isAuthenticated = true
    }

    func signOut() async {
        do {
            try await tokenManager.clearTokens()
            await MainActor.run {
                SettingsManager.shared.disconnectGoogleAccount()
            }
        } catch {
            print("Error clearing tokens: \(error)")
        }
        isAuthenticated = false
    }

    func checkAuthenticationStatus() async {
        let hasTokens = await tokenManager.isAuthenticated
        await MainActor.run {
            self.isAuthenticated = hasTokens
        }
    }

    // MARK: - Private Helpers

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

        try await tokenManager.storeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresIn: tokenResponse.expiresIn
        )
    }

    private func fetchUserInfo() async throws {
        let accessToken = try await tokenManager.getValidAccessToken()

        var request = URLRequest(url: URL(string: GoogleConfig.userInfoEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let userInfo = try JSONDecoder().decode(GoogleUserInfo.self, from: data)

        await MainActor.run {
            let account = GoogleAccount(
                email: userInfo.email,
                displayName: userInfo.name,
                profileImageURL: userInfo.picture.flatMap { URL(string: $0) }
            )
            SettingsManager.shared.googleAccount = account
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
    enum AuthError: Error, LocalizedError {
        case userCancelled
        case sessionError(Error)
        case invalidCallback
        case noAuthorizationCode
        case tokenExchangeFailed(String)
        case networkError(Error)
        case invalidState

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
