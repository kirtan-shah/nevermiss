import Foundation

// MARK: - GoogleAccount

struct GoogleAccount: Codable, Equatable {

    // MARK: - Properties

    let email: String
    let displayName: String?
    let profileImageURL: URL?
    var isConnected: Bool
    var lastSyncDate: Date?

    // MARK: - Initializers

    init(email: String, displayName: String? = nil, profileImageURL: URL? = nil) {
        self.email = email
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.isConnected = true
        self.lastSyncDate = nil
    }
}

// MARK: - GoogleConfig

/// Google API configuration
enum GoogleConfig {

    // MARK: - Properties

    /// OAuth Client ID - Replace with your own from Google Cloud Console
    static let clientID = "791223407722-9an5cccp2bsoc8ork0n2mnstjimahvg7.apps.googleusercontent.com"

    /// OAuth redirect URI (reverse client ID as scheme, required by Google iOS-type credentials)
    static let redirectURI = "com.googleusercontent.apps.791223407722-9an5cccp2bsoc8ork0n2mnstjimahvg7:/oauthredirect"

    /// Callback URL scheme (reverse client ID, without path)
    static let callbackScheme = "com.googleusercontent.apps.791223407722-9an5cccp2bsoc8ork0n2mnstjimahvg7"

    /// Google Calendar API scope (read-only)
    static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    /// User info scope for profile data
    static let userInfoScope = "https://www.googleapis.com/auth/userinfo.email"

    static var scopes: String {
        "\(calendarScope) \(userInfoScope)"
    }

    /// OAuth authorization endpoint
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"

    /// OAuth token endpoint
    static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    /// Google Calendar API base URL
    static let calendarAPIBase = "https://www.googleapis.com/calendar/v3"

    /// User info API endpoint
    static let userInfoEndpoint = "https://www.googleapis.com/oauth2/v2/userinfo"
}
