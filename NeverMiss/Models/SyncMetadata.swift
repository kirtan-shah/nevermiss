import Foundation
import SwiftData

// MARK: - SyncMetadata

@Model
final class SyncMetadata {

    // MARK: - Properties

    @Attribute(.unique) var calendarId: String

    /// Google Calendar sync token for incremental sync
    var syncToken: String?

    var lastFullSync: Date?
    var lastIncrementalSync: Date?
    var calendarSourceRaw: String

    var calendarSource: CalendarSource {
        get { CalendarSource(rawValue: calendarSourceRaw) ?? .google }
        set { calendarSourceRaw = newValue.rawValue }
    }

    // MARK: - Initializers

    init(calendarId: String, calendarSource: CalendarSource) {
        self.calendarId = calendarId
        self.calendarSourceRaw = calendarSource.rawValue
    }
}
