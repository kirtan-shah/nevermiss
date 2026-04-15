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
    var pendingAlerts: [AlertContext] = []

    @ObservationIgnored private let settings = SettingsManager.shared

    /// Regular alert timers, keyed by [eventId: [timerKey: Timer]].
    /// Wiped and re-created on every resync.
    @ObservationIgnored private var activeTimers: [String: [String: Timer]] = [:]

    /// Snooze timers, keyed by event ID. Stored separately so resyncs don't destroy them.
    @ObservationIgnored private var snoozeTimers: [String: Timer] = [:]

    /// Events the user has explicitly joined or dismissed, mapped to the startDate
    /// at dismissal. Survives resyncs so dismissed events don't resurrect, but a
    /// startDate change re-arms alerts (host rescheduled the meeting).
    private var dismissedAlerts: [String: Date] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Actions/Methods

    func rescheduleAlerts(for events: [CalendarEvent]) {
        let upcomingIds = Set(events.map(\.id))
        dismissedAlerts = dismissedAlerts.filter { upcomingIds.contains($0.key) }

        cancelAllAlerts()

        for event in events {
            scheduleAlerts(for: event)
        }
    }

    func scheduleAlerts(for event: CalendarEvent) {
        if let recordedStart = dismissedAlerts[event.id] {
            if recordedStart == event.startDate { return }
            dismissedAlerts.removeValue(forKey: event.id)
        }

        var hasScheduledAlert = false

        for timing in settings.enabledAlertTimings {
            let alertTime = event.startDate.addingTimeInterval(-Double(timing.minutesBefore * 60))

            guard alertTime > Date() else { continue }

            hasScheduledAlert = true
            let timerKey = "alert_\(timing.minutesBefore)"

            scheduleInAppAlert(eventId: event.id, timerKey: timerKey, event: event, timing: timing, alertTime: alertTime)

            let alertId = "\(event.id)_\(timing.minutesBefore)"
            scheduledAlerts.append(ScheduledAlert(
                id: alertId,
                eventId: event.id,
                eventTitle: event.title,
                meetingLink: event.meetingLink,
                scheduledTime: alertTime,
                minutesBefore: timing.minutesBefore
            ))
        }

        // If all alert times have passed but the meeting is ongoing, fire immediately
        if !hasScheduledAlert && event.isOngoing {
            showInAppAlert(for: event, timing: AlertTiming(minutesBefore: 0))
        }
    }

    func cancelAllAlerts() {
        activeTimers.values.flatMap(\.values).forEach { $0.invalidate() }
        activeTimers.removeAll()
        scheduledAlerts.removeAll()
        // snoozeTimers intentionally NOT cleared — they survive resyncs
    }

    func cancelAlerts(for event: CalendarEvent) {
        let eventId = event.id
        dismissedAlerts[eventId] = event.startDate

        activeTimers[eventId]?.values.forEach { $0.invalidate() }
        activeTimers.removeValue(forKey: eventId)

        snoozeTimers[eventId]?.invalidate()
        snoozeTimers.removeValue(forKey: eventId)

        scheduledAlerts.removeAll { $0.eventId == eventId }
        pendingAlerts.removeAll { $0.event.id == eventId }
    }

    func nextAlert(for eventId: String) -> ScheduledAlert? {
        scheduledAlerts
            .filter { $0.eventId == eventId && $0.scheduledTime > Date() }
            .min { $0.scheduledTime < $1.scheduledTime }
    }

    func dismissCurrentAlert() {
        currentAlert = nil
        showNextQueuedAlert()
    }

    func snoozeCurrentAlert(until snoozeTime: Date) {
        guard let alert = currentAlert else { return }
        let eventId = alert.event.id
        dismissCurrentAlert()

        let timeInterval = snoozeTime.timeIntervalSinceNow
        guard timeInterval > 0 else {
            showInAppAlert(for: alert.event, timing: AlertTiming(minutesBefore: 0))
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.snoozeTimers.removeValue(forKey: eventId)
                self?.showInAppAlert(for: alert.event, timing: AlertTiming(minutesBefore: 0))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimers[eventId] = timer
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
        eventId: String,
        timerKey: String,
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
        activeTimers[eventId, default: [:]][timerKey] = timer
    }

    private func showInAppAlert(for event: CalendarEvent, timing: AlertTiming) {
        scheduledAlerts.removeAll { $0.eventId == event.id && $0.minutesBefore == timing.minutesBefore }

        // Same event already showing — update timing in place, no window rebuild
        if let current = currentAlert, current.event.id == event.id {
            currentAlert = AlertContext(event: event, timing: timing)
            return
        }

        // Same event already queued — update its timing
        if let idx = pendingAlerts.firstIndex(where: { $0.event.id == event.id }) {
            pendingAlerts[idx] = AlertContext(event: event, timing: timing)
            return
        }

        let context = AlertContext(event: event, timing: timing)

        // Different event already showing — queue sorted by startDate (soonest first)
        if currentAlert != nil {
            let insertIndex = pendingAlerts.firstIndex { pending in
                event.startDate < pending.event.startDate
            } ?? pendingAlerts.endIndex
            pendingAlerts.insert(context, at: insertIndex)
            return
        }

        // Nothing showing — present immediately
        currentAlert = context
        NotificationCenter.default.post(
            name: .showMeetingAlert,
            object: nil,
            userInfo: [
                "event": event,
                "timing": timing
            ]
        )
    }

    private func showNextQueuedAlert() {
        guard !pendingAlerts.isEmpty else { return }
        let next = pendingAlerts.removeFirst()
        currentAlert = next
        NotificationCenter.default.post(
            name: .showMeetingAlert,
            object: nil,
            userInfo: [
                "event": next.event,
                "timing": next.timing
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
