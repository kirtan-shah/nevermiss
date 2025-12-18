import AppKit

// MARK: - Type Definition

@Observable
@MainActor
final class MeetingScheduler {

    // MARK: - Static Properties

    static let shared = MeetingScheduler()

    // MARK: - Properties

    var scheduledAlerts: [ScheduledAlert] = []
    var currentAlert: AlertContext?

    @ObservationIgnored private let settings = SettingsManager.shared
    @ObservationIgnored private var activeTimers: [String: Timer] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Actions/Methods

    func rescheduleAlerts(for events: [CalendarEvent]) {
        cancelAllAlerts()

        for event in events {
            scheduleAlerts(for: event)
        }
    }

    func scheduleAlerts(for event: CalendarEvent) {
        for timing in settings.enabledAlertTimings {
            let alertTime = event.startDate.addingTimeInterval(-Double(timing.minutesBefore * 60))

            guard alertTime > Date() else { continue }

            let alertId = "\(event.id)_\(timing.minutesBefore)"

            scheduleInAppAlert(id: alertId, event: event, timing: timing, alertTime: alertTime)

            scheduledAlerts.append(ScheduledAlert(
                id: alertId,
                eventId: event.id,
                eventTitle: event.title,
                meetingLink: event.meetingLink,
                scheduledTime: alertTime,
                minutesBefore: timing.minutesBefore
            ))
        }
    }

    func cancelAllAlerts() {
        activeTimers.values.forEach { $0.invalidate() }
        activeTimers.removeAll()
        scheduledAlerts.removeAll()
    }

    func cancelAlerts(for eventId: String) {
        let keysToRemove = activeTimers.keys.filter { $0.hasPrefix(eventId) }
        keysToRemove.forEach { key in
            activeTimers[key]?.invalidate()
            activeTimers.removeValue(forKey: key)
        }
        scheduledAlerts.removeAll { $0.eventId == eventId }
    }

    func nextAlert(for eventId: String) -> ScheduledAlert? {
        scheduledAlerts
            .filter { $0.eventId == eventId && $0.scheduledTime > Date() }
            .min { $0.scheduledTime < $1.scheduledTime }
    }

    func dismissCurrentAlert() {
        currentAlert = nil
    }

    func snoozeCurrentAlert(until snoozeTime: Date) {
        guard let alert = currentAlert else { return }
        dismissCurrentAlert()

        scheduleInAppAlert(
            id: "\(alert.event.id)_snooze_\(UUID().uuidString)",
            event: alert.event,
            timing: AlertTiming(minutesBefore: 0),
            alertTime: snoozeTime
        )
    }

    func snoozeCurrentAlert(for minutes: Int) {
        snoozeCurrentAlert(until: Date().addingTimeInterval(Double(minutes * 60)))
    }

    func joinMeeting() {
        guard let alert = currentAlert,
              let linkString = alert.event.meetingLink,
              let url = URL(string: linkString) else {
            dismissCurrentAlert()
            return
        }

        NSWorkspace.shared.open(url)
        dismissCurrentAlert()
    }

    // MARK: - Private Helpers

    private func scheduleInAppAlert(
        id: String,
        event: CalendarEvent,
        timing: AlertTiming,
        alertTime: Date
    ) {
        let timeInterval = alertTime.timeIntervalSinceNow

        guard timeInterval > 0 else {
            showInAppAlert(for: event, timing: timing)
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showInAppAlert(for: event, timing: timing)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        activeTimers[id] = timer
    }

    private func showInAppAlert(for event: CalendarEvent, timing: AlertTiming) {
        scheduledAlerts.removeAll { $0.eventId == event.id && $0.minutesBefore == timing.minutesBefore }

        currentAlert = AlertContext(event: event, timing: timing)

        NotificationCenter.default.post(
            name: .showMeetingAlert,
            object: nil,
            userInfo: [
                "event": event,
                "timing": timing
            ]
        )
    }
}

// MARK: - Supporting Types

struct ScheduledAlert: Identifiable {
    let id: String
    let eventId: String
    let eventTitle: String
    let meetingLink: String?
    let scheduledTime: Date
    let minutesBefore: Int

    var timeUntilAlert: TimeInterval {
        scheduledTime.timeIntervalSinceNow
    }
}

struct AlertContext {
    let event: CalendarEvent
    let timing: AlertTiming
    let shownAt: Date

    init(event: CalendarEvent, timing: AlertTiming) {
        self.event = event
        self.timing = timing
        self.shownAt = Date()
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let showMeetingAlert = Notification.Name("showMeetingAlert")
}
