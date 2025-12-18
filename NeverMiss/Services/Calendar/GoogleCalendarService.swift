import Foundation

// MARK: - Type Definition

actor GoogleCalendarService {

    // MARK: - Static Properties

    static let shared = GoogleCalendarService()

    // MARK: - Properties

    private let tokenManager = TokenManager.shared
    private let baseURL = GoogleConfig.calendarAPIBase

    // MARK: - Actions/Methods

    func fetchCalendarList() async throws -> [GoogleCalendarListEntry] {
        let url = URL(string: "\(baseURL)/users/me/calendarList")!
        let response: GoogleCalendarListResponse = try await performRequest(url: url)
        return response.items
    }

    func fetchEvents(
        calendarId: String = "primary",
        timeMin: Date? = nil,
        timeMax: Date? = nil,
        maxResults: Int = 250,
        syncToken: String? = nil,
        pageToken: String? = nil
    ) async throws -> GoogleEventsListResponse {
        let encodedCalendarId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedCalendarId)/events")!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]

        // If we have a sync token, use incremental sync
        if let syncToken = syncToken {
            queryItems.append(URLQueryItem(name: "syncToken", value: syncToken))
        } else {
            // Full sync - use time bounds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            if let timeMin = timeMin {
                queryItems.append(URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)))
            }
            if let timeMax = timeMax {
                queryItems.append(URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)))
            }
        }

        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        components.queryItems = queryItems

        return try await performRequest(url: components.url!)
    }

    func fetchAllEvents(
        calendarId: String = "primary",
        timeMin: Date,
        timeMax: Date,
        syncToken: String? = nil
    ) async throws -> (events: [GoogleEvent], syncToken: String?) {
        var allEvents: [GoogleEvent] = []
        var currentPageToken: String? = nil
        var finalSyncToken: String? = nil

        repeat {
            let response = try await fetchEvents(
                calendarId: calendarId,
                timeMin: syncToken == nil ? timeMin : nil,
                timeMax: syncToken == nil ? timeMax : nil,
                syncToken: syncToken,
                pageToken: currentPageToken
            )

            allEvents.append(contentsOf: response.items)
            currentPageToken = response.nextPageToken
            finalSyncToken = response.nextSyncToken

        } while currentPageToken != nil

        return (allEvents, finalSyncToken)
    }

    // MARK: - Private Helpers

    private func performRequest<T: Decodable>(url: URL) async throws -> T {
        let accessToken = try await tokenManager.getValidAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CalendarAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw CalendarAPIError.decodingError(error)
            }
        case 401:
            throw CalendarAPIError.unauthorized
        case 403:
            throw CalendarAPIError.forbidden
        case 404:
            throw CalendarAPIError.notFound
        case 410:
            throw CalendarAPIError.syncTokenExpired
        case 429:
            throw CalendarAPIError.rateLimited
        default:
            throw CalendarAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Supporting Types

extension GoogleCalendarService {
    enum CalendarAPIError: Error, LocalizedError {
        case invalidResponse
        case unauthorized
        case forbidden
        case notFound
        case syncTokenExpired
        case rateLimited
        case serverError(statusCode: Int)
        case decodingError(Error)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid response from server"
            case .unauthorized: return "Authentication required"
            case .forbidden: return "Access denied to calendar"
            case .notFound: return "Calendar not found"
            case .syncTokenExpired: return "Sync token expired, full sync required"
            case .rateLimited: return "Too many requests, please try again later"
            case .serverError(let code): return "Server error (HTTP \(code))"
            case .decodingError(let error): return "Data parsing error: \(error.localizedDescription)"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            }
        }
    }
}

struct GoogleCalendarListResponse: Codable {
    let kind: String
    let etag: String
    let nextPageToken: String?
    let nextSyncToken: String?
    let items: [GoogleCalendarListEntry]
}

struct GoogleCalendarListEntry: Codable, Identifiable {
    let id: String
    let summary: String?
    let description: String?
    let timeZone: String?
    let colorId: String?
    let backgroundColor: String?
    let foregroundColor: String?
    let selected: Bool?
    let accessRole: String?
    let primary: Bool?
}

struct GoogleEventsListResponse: Codable {
    let kind: String
    let etag: String
    let summary: String?
    let updated: String?
    let timeZone: String?
    let nextPageToken: String?
    let nextSyncToken: String?
    let items: [GoogleEvent]
}

struct GoogleEvent: Codable, Identifiable {
    let id: String
    let status: String?
    let htmlLink: String?
    let created: String?
    let updated: String?
    let summary: String?
    let description: String?
    let location: String?
    let creator: GoogleEventPerson?
    let organizer: GoogleEventPerson?
    let start: GoogleEventDateTime
    let end: GoogleEventDateTime
    let recurringEventId: String?
    let transparency: String?
    let visibility: String?
    let attendees: [GoogleEventAttendee]?
    let hangoutLink: String?
    let conferenceData: GoogleConferenceData?
    let etag: String
}

struct GoogleEventDateTime: Codable {
    let date: String?
    let dateTime: String?
    let timeZone: String?

    var asDate: Date? {
        if let dateTime = dateTime {
            return ISO8601DateFormatter().date(from: dateTime)
        } else if let date = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: date)
        }
        return nil
    }

    var isAllDay: Bool {
        date != nil && dateTime == nil
    }
}

struct GoogleEventPerson: Codable {
    let id: String?
    let email: String?
    let displayName: String?
    let selfValue: Bool?

    enum CodingKeys: String, CodingKey {
        case id, email, displayName
        case selfValue = "self"
    }
}

struct GoogleEventAttendee: Codable {
    let id: String?
    let email: String?
    let displayName: String?
    let organizer: Bool?
    let selfValue: Bool?
    let resource: Bool?
    let optional: Bool?
    let responseStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, email, displayName, organizer, resource, optional, responseStatus
        case selfValue = "self"
    }
}

struct GoogleConferenceData: Codable {
    let entryPoints: [GoogleEntryPoint]?
    let conferenceSolution: GoogleConferenceSolution?
    let conferenceId: String?
}

struct GoogleEntryPoint: Codable {
    let entryPointType: String?
    let uri: String?
    let label: String?
    let pin: String?
    let meetingCode: String?
}

struct GoogleConferenceSolution: Codable {
    let key: GoogleConferenceSolutionKey?
    let name: String?
    let iconUri: String?
}

struct GoogleConferenceSolutionKey: Codable {
    let type: String?
}
