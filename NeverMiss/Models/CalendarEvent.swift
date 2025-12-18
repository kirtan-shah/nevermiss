import Foundation
import SwiftData

// MARK: - CalendarSource

enum CalendarSource: String, Codable {
    case google = "google"
    case eventKit = "eventKit"
}

// MARK: - CalendarEvent

@Model
final class CalendarEvent {

    // MARK: - Properties

    @Attribute(.unique) var id: String
    var title: String
    var eventDescription: String?
    var startDate: Date
    var endDate: Date
    var meetingLink: String?
    var location: String?
    var calendarId: String
    var calendarName: String
    var calendarSourceRaw: String
    var isAllDay: Bool
    var organizerEmail: String?
    var organizerName: String?
    var lastSynced: Date

    /// ETag for Google Calendar sync
    var etag: String?

    var calendarSource: CalendarSource {
        get { CalendarSource(rawValue: calendarSourceRaw) ?? .google }
        set { calendarSourceRaw = newValue.rawValue }
    }

    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSinceNow
    }

    var isUpcoming: Bool {
        startDate > Date()
    }

    var isOngoing: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }

    var durationMinutes: Int {
        Int(endDate.timeIntervalSince(startDate) / 60)
    }

    // MARK: - Initializers

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarId: String,
        calendarName: String,
        calendarSource: CalendarSource
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarId = calendarId
        self.calendarName = calendarName
        self.calendarSourceRaw = calendarSource.rawValue
        self.isAllDay = false
        self.lastSynced = Date()
    }
}

// MARK: - Formatted Display

extension CalendarEvent {
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(startDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: startDate)
        }
    }

    var relativeTimeUntilStart: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: startDate, relativeTo: Date())
    }
}
