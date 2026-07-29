import AppKit

// MARK: - Type Definition

@Observable
@MainActor
final class MeetingScheduler: NSObject {

    // MARK: - Static Properties

    static let shared = MeetingScheduler()

    // MARK: - Properties

    var scheduledAlerts: [ScheduledAlert] = []
    var currentAlert: AlertContext?
    var pendingAlerts: [AlertContext] = []

    @ObservationIgnored private let settings = SettingsManager.shared
    @ObservationIgnored private var notificationDeliveryEnabled = true

    /// Regular alert timers, keyed by [eventId: [timerKey: Timer]].
    /// Wiped and re-created on every resync.
    @ObservationIgnored private var activeTimers: [String: [String: Timer]] = [:]

    /// Snooze timers, keyed by event ID. Stored separately so resyncs don't destroy them.
    @ObservationIgnored private var snoozeTimers: [String: Timer] = [:]

    /// Tokens captured by snooze callbacks. Invalidated callbacks become no-ops even
    /// if timer delivery was already queued when the timer was cancelled.
    @ObservationIgnored private var snoozeGenerations: [String: UUID] = [:]

    /// Active snooze deadlines keyed by event ID. Used to suppress regular alert
    /// scheduling while a user-requested snooze is still in effect.
    @ObservationIgnored private var snoozedUntil: [String: Date] = [:]

    /// Occurrences whose alert lifecycle is now explicitly user-driven by Snooze.
    /// This survives the event leaving the upcoming set (for example when it ends)
    /// so the promised snooze still fires and can be snoozed again.
    @ObservationIgnored private var snoozeChainStartDates: [String: Date] = [:]

    /// Tokens captured by regular timer callbacks. Rebuilding or cancelling an
    /// event's schedule invalidates every callback from the previous schedule.
    @ObservationIgnored private var regularTimerGenerations: [String: UUID] = [:]

    /// Last known start date for each event with scheduler state. Used to preserve
    /// alert/snooze chains across resyncs unless the meeting time actually changed.
    @ObservationIgnored private var trackedEventStartDates: [String: Date] = [:]

    /// Freshest event object received from sync, keyed by event ID. Timer callbacks
    /// use this instead of the object captured when the timer was first created.
    @ObservationIgnored private var trackedEvents: [String: CalendarEvent] = [:]

    /// Events the user has explicitly joined or dismissed, mapped to the startDate
    /// at dismissal. Survives resyncs so dismissed events don't resurrect, but a
    /// startDate change re-arms alerts (host rescheduled the meeting).
    private var dismissedAlerts: [String: DismissedOccurrence] = [:]

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Actions/Methods

    func rescheduleAlerts(for events: [CalendarEvent]) {
        // A uniqueness violation in persisted data should not crash the scheduler.
        // SwiftData normally enforces this, but choosing the last fetched value is a
        // safer recovery behavior during migrations or store repair.
        var eventsById: [String: CalendarEvent] = [:]
        for event in events {
            eventsById[event.id] = event
        }

        let now = Date()
        dismissedAlerts = dismissedAlerts.filter { $0.value.expiresAt > now }

        let knownIds = Set(trackedEventStartDates.keys)
            .union(trackedEvents.keys)
            .union(activeTimers.keys)
            .union(snoozeTimers.keys)
            .union(scheduledAlerts.map(\.eventId))
            .union(pendingAlerts.map(\.event.id))
            .union(currentAlert.map { [$0.event.id] } ?? [])

        for eventId in knownIds where eventsById[eventId] == nil {
            if let chainStart = snoozeChainStartDates[eventId],
               trackedEventStartDates[eventId] == chainStart {
                // CalendarSyncManager intentionally supplies only upcoming/ongoing
                // events. An explicit snooze must outlive that filtered list.
                cancelRegularAlerts(for: eventId)
                continue
            }

            clearEventState(eventId: eventId)
        }

        for event in eventsById.values {
            if let trackedStart = trackedEventStartDates[event.id],
               trackedStart != event.startDate {
                clearEventState(eventId: event.id)
            }

            trackedEventStartDates[event.id] = event.startDate
            trackedEvents[event.id] = event
            refreshAlertContexts(for: event)
            rebuildRegularAlerts(for: event)
        }
    }

    func scheduleAlerts(for event: CalendarEvent) {
        if let trackedStart = trackedEventStartDates[event.id],
           trackedStart != event.startDate {
            clearEventState(eventId: event.id)
        }

        trackedEventStartDates[event.id] = event.startDate
        trackedEvents[event.id] = event
        refreshAlertContexts(for: event)
        rebuildRegularAlerts(for: event)
    }

    func cancelAllAlerts() {
        activeTimers.values.flatMap(\.values).forEach { $0.invalidate() }
        activeTimers.removeAll()
        regularTimerGenerations.removeAll()
        scheduledAlerts.removeAll()
        // Snooze timers intentionally survive schedule rebuilds. App termination
        // tears down the process and its run loop, so they require no special work.
    }

    func cancelAlerts(for event: CalendarEvent) {
        let eventId = event.id

        // A window for an old occurrence must not cancel a newly rescheduled one
        // that happens to reuse the same provider event ID.
        if let trackedStart = trackedEventStartDates[eventId],
           trackedStart != event.startDate {
            return
        }

        dismissedAlerts[eventId] = DismissedOccurrence(
            startDate: event.startDate,
            expiresAt: max(event.endDate, Date()).addingTimeInterval(3600)
        )

        cancelRegularAlerts(for: eventId)
        cancelSnooze(for: eventId)

        trackedEventStartDates.removeValue(forKey: eventId)
        trackedEvents.removeValue(forKey: eventId)
        pendingAlerts.removeAll { $0.event.id == eventId }
    }

    func nextAlert(for eventId: String) -> ScheduledAlert? {
        scheduledAlerts
            .filter { $0.eventId == eventId && $0.scheduledTime > Date() }
            .min { $0.scheduledTime < $1.scheduledTime }
    }

    func dismissCurrentAlert(eventId: String? = nil, startDate: Date? = nil) {
        guard let currentAlert else { return }
        if let eventId, currentAlert.event.id != eventId { return }
        if let startDate, currentAlert.event.startDate != startDate { return }

        self.currentAlert = nil
        showNextQueuedAlert()
    }

    func snoozeCurrentAlert(until snoozeTime: Date) {
        guard let alert = currentAlert else { return }
        snoozeAlert(for: alert.event, until: snoozeTime)
    }

    func snoozeAlert(for event: CalendarEvent, until snoozeTime: Date) {
        let eventId = event.id

        // Do not apply an action from a stale window to a newly rescheduled
        // occurrence that happens to have the same provider event ID.
        if let trackedStart = trackedEventStartDates[eventId],
           trackedStart != event.startDate {
            dismissCurrentAlert(eventId: eventId, startDate: event.startDate)
            return
        }

        dismissCurrentAlert(eventId: eventId)
        pendingAlerts.removeAll { $0.event.id == eventId }
        cancelSnooze(for: eventId, endChain: false)

        trackedEventStartDates[eventId] = event.startDate
        trackedEvents[eventId] = event
        snoozeChainStartDates[eventId] = event.startDate

        let timeInterval = snoozeTime.timeIntervalSinceNow
        guard timeInterval > 0 else {
            showInAppAlert(for: event, timing: snoozeTiming(for: event))
            return
        }

        let generation = UUID()
        let startDate = event.startDate
        snoozedUntil[eventId] = snoozeTime
        snoozeGenerations[eventId] = generation

        let timer = makeTimer(
            after: timeInterval,
            action: .snooze(
                eventId: eventId,
                startDate: startDate,
                generation: generation
            )
        )
        snoozeTimers[eventId] = timer

        // The explicit snooze callback replaces regular alerts at or before its
        // deadline. Later configured alerts remain scheduled as before.
        rebuildRegularAlerts(for: event)
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
        cancelAlerts(for: alert.event)
        dismissCurrentAlert(eventId: alert.event.id, startDate: alert.event.startDate)
    }

    // MARK: - Private Helpers

    private func makeTimer(after interval: TimeInterval, action: SchedulerTimerAction) -> Timer {
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(handleScheduledTimer(_:)),
            userInfo: SchedulerTimerPayload(action: action),
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @objc private func handleScheduledTimer(_ timer: Timer) {
        guard let payload = timer.userInfo as? SchedulerTimerPayload else { return }

        switch payload.action {
        case .snooze(let eventId, let startDate, let generation):
            fireSnoozedAlert(
                eventId: eventId,
                startDate: startDate,
                generation: generation
            )

        case .regular(let eventId, let timerKey, let timing, let generation):
            fireRegularAlert(
                eventId: eventId,
                timerKey: timerKey,
                timing: timing,
                generation: generation
            )
        }
    }

    private func rebuildRegularAlerts(for event: CalendarEvent) {
        let eventId = event.id
        cancelRegularAlerts(for: eventId)

        if let dismissedOccurrence = dismissedAlerts[eventId] {
            if dismissedOccurrence.startDate == event.startDate { return }
            dismissedAlerts.removeValue(forKey: eventId)
        }

        let now = Date()
        let snoozeDeadline = activeSnoozeDeadline(for: eventId, startDate: event.startDate)
        let generation = UUID()
        regularTimerGenerations[eventId] = generation

        var hasScheduledAlert = false

        for timing in settings.enabledAlertTimings {
            let alertTime = event.startDate.addingTimeInterval(-Double(timing.minutesBefore * 60))

            guard alertTime > now else { continue }
            guard snoozeDeadline.map({ alertTime > $0 }) ?? true else { continue }

            hasScheduledAlert = true
            let timerKey = "alert_\(timing.minutesBefore)"

            scheduleInAppAlert(
                eventId: eventId,
                timerKey: timerKey,
                timing: timing,
                alertTime: alertTime,
                generation: generation
            )

            let alertId = "\(eventId)_\(timing.minutesBefore)"
            scheduledAlerts.append(ScheduledAlert(
                id: alertId,
                eventId: eventId,
                eventTitle: event.title,
                meetingLink: event.meetingLink,
                scheduledTime: alertTime,
                minutesBefore: timing.minutesBefore
            ))
        }

        // If all alert times have passed but the meeting is ongoing, fire immediately
        if !hasScheduledAlert && snoozeDeadline == nil && event.isOngoing {
            showInAppAlert(for: event, timing: AlertTiming(minutesBefore: 0))
        }
    }

    private func cancelRegularAlerts(for eventId: String) {
        activeTimers[eventId]?.values.forEach { $0.invalidate() }
        activeTimers.removeValue(forKey: eventId)
        regularTimerGenerations.removeValue(forKey: eventId)
        scheduledAlerts.removeAll { $0.eventId == eventId }
    }

    private func cancelSnooze(for eventId: String, endChain: Bool = true) {
        snoozeTimers[eventId]?.invalidate()
        snoozeTimers.removeValue(forKey: eventId)
        snoozedUntil.removeValue(forKey: eventId)
        snoozeGenerations.removeValue(forKey: eventId)
        if endChain {
            snoozeChainStartDates.removeValue(forKey: eventId)
        }
    }

    private func activeSnoozeDeadline(for eventId: String, startDate: Date) -> Date? {
        guard snoozeTimers[eventId] != nil,
              snoozeGenerations[eventId] != nil,
              trackedEventStartDates[eventId] == startDate else {
            return nil
        }
        return snoozedUntil[eventId]
    }

    private func snoozeTiming(for event: CalendarEvent) -> AlertTiming {
        let minutes = max(0, Int(ceil(event.startDate.timeIntervalSinceNow / 60)))
        return AlertTiming(minutesBefore: minutes)
    }

    private func fireSnoozedAlert(eventId: String, startDate: Date, generation: UUID) {
        guard snoozeGenerations[eventId] == generation,
              trackedEventStartDates[eventId] == startDate,
              let event = trackedEvents[eventId] else {
            return
        }

        cancelSnooze(for: eventId, endChain: false)
        showInAppAlert(for: event, timing: snoozeTiming(for: event))
    }

    private func clearEventState(eventId: String) {
        cancelRegularAlerts(for: eventId)
        cancelSnooze(for: eventId)
        trackedEventStartDates.removeValue(forKey: eventId)
        trackedEvents.removeValue(forKey: eventId)
        pendingAlerts.removeAll { $0.event.id == eventId }

        // Keep the logical current alert until its AppKit window finishes dismissal.
        // Advancing here would post the next alert while the old window is still up,
        // causing AlertWindowController to reject it as a duplicate presentation.
    }

    private func refreshAlertContexts(for event: CalendarEvent) {
        if let current = currentAlert,
           current.event.id == event.id,
           current.event.startDate == event.startDate {
            currentAlert = AlertContext(
                event: event,
                timing: current.timing,
                shownAt: current.shownAt
            )
        }

        if let idx = pendingAlerts.firstIndex(where: {
            $0.event.id == event.id && $0.event.startDate == event.startDate
        }) {
            pendingAlerts[idx] = AlertContext(
                event: event,
                timing: pendingAlerts[idx].timing,
                shownAt: pendingAlerts[idx].shownAt
            )
        }
    }

    private func scheduleInAppAlert(
        eventId: String,
        timerKey: String,
        timing: AlertTiming,
        alertTime: Date,
        generation: UUID
    ) {
        let timeInterval = alertTime.timeIntervalSinceNow

        guard timeInterval > 0 else {
            fireRegularAlert(
                eventId: eventId,
                timerKey: timerKey,
                timing: timing,
                generation: generation
            )
            return
        }

        let timer = makeTimer(
            after: timeInterval,
            action: .regular(
                eventId: eventId,
                timerKey: timerKey,
                timing: timing,
                generation: generation
            )
        )
        activeTimers[eventId, default: [:]][timerKey] = timer
    }

    private func fireRegularAlert(
        eventId: String,
        timerKey: String,
        timing: AlertTiming,
        generation: UUID
    ) {
        guard regularTimerGenerations[eventId] == generation,
              let event = trackedEvents[eventId],
              trackedEventStartDates[eventId] == event.startDate,
              activeSnoozeDeadline(for: eventId, startDate: event.startDate) == nil,
              dismissedAlerts[eventId]?.startDate != event.startDate else {
            return
        }

        activeTimers[eventId]?.removeValue(forKey: timerKey)
        if activeTimers[eventId]?.isEmpty == true {
            activeTimers.removeValue(forKey: eventId)
        }
        showInAppAlert(for: event, timing: timing)
    }

    private func showInAppAlert(for event: CalendarEvent, timing: AlertTiming) {
        guard trackedEventStartDates[event.id] == event.startDate,
              dismissedAlerts[event.id]?.startDate != event.startDate,
              activeSnoozeDeadline(for: event.id, startDate: event.startDate) == nil else {
            return
        }

        scheduledAlerts.removeAll { $0.eventId == event.id && $0.minutesBefore == timing.minutesBefore }

        if let current = currentAlert,
           current.event.id == event.id,
           current.event.startDate == event.startDate {
            currentAlert = AlertContext(event: event, timing: timing, shownAt: current.shownAt)
            return
        }

        if let idx = pendingAlerts.firstIndex(where: {
            $0.event.id == event.id && $0.event.startDate == event.startDate
        }) {
            pendingAlerts[idx] = AlertContext(event: event, timing: timing)
            return
        }

        let context = AlertContext(event: event, timing: timing)

        if currentAlert != nil {
            let insertIndex = pendingAlerts.firstIndex { pending in
                event.startDate < pending.event.startDate
            } ?? pendingAlerts.endIndex
            pendingAlerts.insert(context, at: insertIndex)
            return
        }

        currentAlert = context
        postAlertNotification(for: event, timing: timing)
    }

    private func showNextQueuedAlert() {
        while !pendingAlerts.isEmpty {
            let next = pendingAlerts.removeFirst()
            let event = next.event

            guard trackedEventStartDates[event.id] == event.startDate,
                  dismissedAlerts[event.id]?.startDate != event.startDate,
                  activeSnoozeDeadline(for: event.id, startDate: event.startDate) == nil else {
                continue
            }

            currentAlert = next
            postAlertNotification(for: event, timing: next.timing)
            return
        }
    }

    private func postAlertNotification(for event: CalendarEvent, timing: AlertTiming) {
        guard notificationDeliveryEnabled else { return }

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

private enum SchedulerTimerAction {
    case snooze(eventId: String, startDate: Date, generation: UUID)
    case regular(eventId: String, timerKey: String, timing: AlertTiming, generation: UUID)
}

private struct DismissedOccurrence {
    let startDate: Date
    let expiresAt: Date
}

private final class SchedulerTimerPayload: NSObject {
    let action: SchedulerTimerAction

    init(action: SchedulerTimerAction) {
        self.action = action
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

    init(event: CalendarEvent, timing: AlertTiming, shownAt: Date = Date()) {
        self.event = event
        self.timing = timing
        self.shownAt = shownAt
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let showMeetingAlert = Notification.Name("showMeetingAlert")
}

#if DEBUG
extension MeetingScheduler {
    func resetStateForTesting() {
        notificationDeliveryEnabled = false
        activeTimers.values.flatMap(\.values).forEach { $0.invalidate() }
        activeTimers.removeAll()
        regularTimerGenerations.removeAll()

        snoozeTimers.values.forEach { $0.invalidate() }
        snoozeTimers.removeAll()

        snoozeGenerations.removeAll()
        snoozedUntil.removeAll()
        snoozeChainStartDates.removeAll()
        trackedEventStartDates.removeAll()
        trackedEvents.removeAll()
        dismissedAlerts.removeAll()
        scheduledAlerts.removeAll()
        pendingAlerts.removeAll()
        currentAlert = nil
    }

    func isSnoozedForTesting(eventId: String) -> Bool {
        snoozeTimers[eventId] != nil && snoozedUntil[eventId] != nil
    }

    func attemptToShowAlertForTesting(event: CalendarEvent) {
        showInAppAlert(for: event, timing: AlertTiming(minutesBefore: 0))
    }
}
#endif
