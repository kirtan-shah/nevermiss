import EventKit

// MARK: - Type Definition

@Observable
@MainActor
final class EventKitService {

    // MARK: - Static Properties

    static let shared = EventKitService()

    // MARK: - Properties

    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var calendars: [EKCalendar] = []
    var isAuthorized = false

    @ObservationIgnored private let eventStore = EKEventStore()

    // MARK: - Initialization

    init() {
        updateAuthorizationStatus()
        setupNotifications()
    }

    // MARK: - Actions/Methods

    func requestAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized, .fullAccess:
            await updateState(authorized: true)
            return true

        case .notDetermined:
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            await updateState(authorized: granted)
            return granted

        case .denied:
            throw EventKitError.accessDenied

        case .restricted:
            throw EventKitError.accessRestricted

        case .writeOnly:
            // Write-only access is not sufficient for reading events
            throw EventKitError.accessDenied

        @unknown default:
            throw EventKitError.accessDenied
        }
    }

    func loadCalendars() {
        calendars = eventStore.calendars(for: .event)
    }

    func getCalendarInfoList() -> [CalendarInfo] {
        loadCalendars()
        return calendars.map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                name: calendar.title,
                color: calendar.cgColor?.hexString ?? "#007AFF",
                accountName: calendar.source.title,
                source: .eventKit,
                isSelected: false
            )
        }
    }

    func fetchEvents(
        from startDate: Date,
        to endDate: Date,
        calendarIds: [String]? = nil
    ) throws -> [EKEvent] {
        guard isAuthorized else {
            throw EventKitError.accessDenied
        }

        let calendarsToSearch: [EKCalendar]
        if let ids = calendarIds {
            calendarsToSearch = calendars.filter { ids.contains($0.calendarIdentifier) }
        } else {
            calendarsToSearch = calendars
        }

        guard !calendarsToSearch.isEmpty else {
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendarsToSearch
        )

        return eventStore.events(matching: predicate)
    }

    func convertToCalendarEvent(_ ekEvent: EKEvent) -> CalendarEvent {
        let event = CalendarEvent(
            id: "ek_\(ekEvent.eventIdentifier)",
            title: ekEvent.title ?? "Untitled Event",
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            calendarId: ekEvent.calendar.calendarIdentifier,
            calendarName: ekEvent.calendar.title,
            calendarSource: .eventKit
        )

        event.eventDescription = ekEvent.notes
        event.location = ekEvent.location
        event.isAllDay = ekEvent.isAllDay
        event.meetingLink = extractMeetingLink(from: ekEvent)
        event.organizerName = ekEvent.organizer?.name

        return event
    }

    func fetchCalendarEvents(
        from startDate: Date,
        to endDate: Date,
        calendarIds: [String]? = nil
    ) throws -> [CalendarEvent] {
        let ekEvents = try fetchEvents(from: startDate, to: endDate, calendarIds: calendarIds)
        return ekEvents.map { convertToCalendarEvent($0) }
    }

    // MARK: - Private Helpers

    private func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = authorizationStatus == .authorized || authorizationStatus == .fullAccess
    }

    private func updateState(authorized: Bool) async {
        isAuthorized = authorized
        updateAuthorizationStatus()
        if authorized {
            loadCalendars()
        }
    }

    private func extractMeetingLink(from event: EKEvent) -> String? {
        // Check URL property
        if let url = event.url?.absoluteString {
            if isMeetingLink(url) {
                return url
            }
        }

        // Check location
        if let location = event.location, isMeetingLink(location) {
            return extractURL(from: location)
        }

        // Check notes
        if let notes = event.notes {
            return extractURL(from: notes)
        }

        return nil
    }

    private func isMeetingLink(_ string: String) -> Bool {
        let meetingPatterns = [
            "zoom.us",
            "meet.google.com",
            "teams.microsoft.com",
            "webex.com",
            "gotomeeting.com",
            "whereby.com",
            "around.co",
            "cal.com"
        ]
        let lowercased = string.lowercased()
        return meetingPatterns.contains { lowercased.contains($0) }
    }

    private func extractURL(from string: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))

        for match in matches ?? [] {
            if let range = Range(match.range, in: string) {
                let url = String(string[range])
                if isMeetingLink(url) {
                    return url
                }
            }
        }
        return nil
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }

    @objc private func eventStoreChanged(_ notification: Notification) {
        loadCalendars()
        // Post notification for sync manager
        NotificationCenter.default.post(name: .calendarDataChanged, object: nil)
    }
}

// MARK: - Supporting Types

extension EventKitService {
    enum EventKitError: Error, LocalizedError {
        case accessDenied
        case accessRestricted
        case fetchFailed(Error)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Calendar access was denied. Please enable it in System Settings > Privacy & Security > Calendars."
            case .accessRestricted:
                return "Calendar access is restricted on this device."
            case .fetchFailed(let error):
                return "Failed to fetch calendar events: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let calendarDataChanged = Notification.Name("calendarDataChanged")
}

private extension CGColor {
    var hexString: String {
        guard let components = components, components.count >= 3 else {
            return "#007AFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
