import Foundation
import SwiftData
import Combine

// MARK: - Type Definition

@Observable
@MainActor
final class CalendarSyncManager {

    // MARK: - Static Properties

    static let shared = CalendarSyncManager()

    // MARK: - Properties

    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: Error?
    var upcomingEvents: [CalendarEvent] = []
    var availableCalendars: [CalendarInfo] = []

    @ObservationIgnored private let googleCalendarService = GoogleCalendarService.shared
    @ObservationIgnored private let eventKitService = EventKitService.shared
    @ObservationIgnored private let settings = SettingsManager.shared

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var syncTimer: Timer?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var pendingForcedSync = false

    /// Sync window: 7 days past to 30 days future
    @ObservationIgnored private let pastDays: Int = 7
    @ObservationIgnored private let futureDays: Int = 30

    /// Manual sync cooldown (5 minutes)
    @ObservationIgnored private let minManualSyncInterval: TimeInterval = 300
    @ObservationIgnored private var lastManualSyncStarted: Date?

    var canManualSync: Bool {
        guard let last = lastManualSyncStarted else { return true }
        return Date().timeIntervalSince(last) >= minManualSyncInterval
    }

    var manualSyncCooldownRemaining: Int {
        guard let last = lastManualSyncStarted else { return 0 }
        return max(0, Int(ceil((minManualSyncInterval - Date().timeIntervalSince(last)) / 60)))
    }

    // MARK: - Initialization

    private init() {
        setupObservers()
    }

    // MARK: - Actions/Methods

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    func startPeriodicSync() {
        scheduleAlignedSync()
    }

    /// Schedules syncs to fire 15 seconds before each interval boundary on the clock.
    /// With a 5-min interval: :59:45, :04:45, :09:45, :14:45, ...
    /// With a 10-min interval: :59:45, :09:45, :19:45, ...
    /// This ensures fresh data is available just before meetings that start on round times.
    private func scheduleAlignedSync() {
        let intervalSeconds = TimeInterval(settings.syncInterval * 60)
        let leadTime: TimeInterval = 15
        let now = Date()
        let secondsSinceMidnight = now.timeIntervalSince(Calendar.current.startOfDay(for: now))

        // Find the next interval boundary (e.g., :00, :05, :10, ...) then subtract 15s
        let nextBoundary = (floor(secondsSinceMidnight / intervalSeconds) + 1) * intervalSeconds
        let firstFireDelay = max(1, (nextBoundary - leadTime) - secondsSinceMidnight)

        syncTimer = Timer.scheduledTimer(withTimeInterval: firstFireDelay, repeats: false) { [weak self] _ in
            // This timer is installed on the main run loop. Restore that isolation
            // explicitly before replacing the observable service's timer state.
            MainActor.assumeIsolated {
                self?.beginRepeatingSync(intervalSeconds: intervalSeconds)
            }
        }
        RunLoop.main.add(syncTimer!, forMode: .common)
    }

    private func beginRepeatingSync(intervalSeconds: TimeInterval) {
        Task { @MainActor [weak self] in
            await self?.performSync(force: true)
        }

        // Continue at the exact interval from the aligned first-fire point.
        let repeating = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performSync(force: true)
            }
        }
        RunLoop.main.add(repeating, forMode: .common)
        syncTimer = repeating
    }

    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func performSync(force: Bool = false) async {
        if isSyncing {
            // EventKit and settings notifications can arrive while a network sync is
            // suspended. Coalesce them into one follow-up pass instead of dropping
            // a calendar change that may have happened after this pass fetched it.
            if force {
                pendingForcedSync = true
            }
            return
        }
        if !force && !canManualSync { return }
        if !force { lastManualSyncStarted = Date() }

        isSyncing = true
        defer {
            isSyncing = false
        }

        repeat {
            pendingForcedSync = false
            await performSyncPass()
        } while pendingForcedSync
    }

    private func performSyncPass() async {
        syncError = nil

        let now = Date()
        let timeMin = Calendar.current.date(byAdding: .day, value: -pastDays, to: now)!
        let timeMax = Calendar.current.date(byAdding: .day, value: futureDays, to: now)!

        // Sync from both sources concurrently
        async let googleSync: Void = syncGoogleCalendars(timeMin: timeMin, timeMax: timeMax)
        async let eventKitSync: Void = syncEventKitCalendars(timeMin: timeMin, timeMax: timeMax)

        var sourceErrors: [Error] = []

        do {
            try await googleSync
        } catch {
            sourceErrors.append(error)
        }

        do {
            try await eventKitSync
        } catch {
            sourceErrors.append(error)
        }

        if sourceErrors.contains(where: { error in
            if let tokenError = error as? TokenManager.TokenError {
                return tokenError.requiresReauthentication
            }
            if let calendarError = error as? GoogleCalendarService.CalendarAPIError {
                return calendarError.requiresReauthentication
            }
            return false
        }) {
            await GoogleAuthService.shared.handleTokenExpired()
        }

        // A source or individual Google calendar may have saved valid changes before
        // another source failed. Always refresh the in-memory list and scheduler once
        // both tasks settle so moved meetings do not retain stale alert timers.
        refreshUpcomingEvents()
        MeetingScheduler.shared.rescheduleAlerts(for: upcomingEvents)

        if sourceErrors.isEmpty {
            lastSyncDate = now
            settings.lastSyncDate = now
            cleanOldEvents()
            return
        }

        syncError = sourceErrors[0]
        for error in sourceErrors {
            print("Sync error: \(error)")
        }
    }

    func refreshCalendarList() async {
        // Keep last-known entries for a source when a transient refresh fails. If
        // Google entries are replaced with an empty list after an offline launch,
        // later event syncs can no longer determine which selected IDs are Google.
        var calendars = availableCalendars

        // Get Google calendars
        if GoogleAuthService.shared.isAuthenticated {
            do {
                let entries = try await googleCalendarService.fetchCalendarList()
                calendars.removeAll { $0.source == .google }
                calendars.append(contentsOf: googleCalendarInfos(from: entries))
            } catch let tokenError as TokenManager.TokenError {
                if tokenError.requiresReauthentication {
                    await GoogleAuthService.shared.handleTokenExpired()
                }
                print("Failed to fetch Google calendars: \(tokenError)")
            } catch let calendarError as GoogleCalendarService.CalendarAPIError {
                if calendarError.requiresReauthentication {
                    await GoogleAuthService.shared.handleTokenExpired()
                }
                print("Failed to fetch Google calendars: \(calendarError)")
            } catch {
                print("Failed to fetch Google calendars: \(error)")
            }
        } else {
            calendars.removeAll { $0.source == .google }
        }

        // Get EventKit calendars
        if eventKitService.isAuthorized {
            calendars.removeAll { $0.source == .eventKit }
            let ekCalendars = eventKitService.getCalendarInfoList()
            calendars.append(contentsOf: ekCalendars.map { info in
                var mutableInfo = info
                mutableInfo.isSelected = settings.selectedCalendarIds.contains(info.id)
                return mutableInfo
            })
        } else {
            calendars.removeAll { $0.source == .eventKit }
        }

        availableCalendars = calendars

        // Re-evaluate cached-event eligibility whenever account state changes.
        // Temporary credential loss keeps cached meetings; an explicit disconnect,
        // which removes the saved account identity, stops them.
        if !GoogleAuthService.shared.isAuthenticated {
            refreshUpcomingEvents()
            MeetingScheduler.shared.rescheduleAlerts(for: upcomingEvents)
        }

        // Auto-select primary calendars if none selected
        if settings.selectedCalendarIds.isEmpty {
            let primaryIds = calendars
                .filter { $0.isPrimary || $0.id == settings.googleAccount?.email }
                .map { $0.id }
            if !primaryIds.isEmpty {
                settings.selectCalendars(primaryIds)
            }
        }
    }

    func getUpcomingEvents(within hours: Int = 24) -> [CalendarEvent] {
        guard let context = modelContext else { return [] }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .hour, value: hours, to: now)!
        let selectedIds = Array(settings.selectedCalendarIds)

        let predicate = #Predicate<CalendarEvent> { event in
            event.endDate > now && event.startDate <= endDate && !event.isAllDay
            && selectedIds.contains(event.calendarId)
        }

        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate)]
        )

        let events = (try? context.fetch(descriptor)) ?? []
        let includeGoogleEvents = Self.shouldIncludeCachedGoogleEvents(
            isAuthenticated: GoogleAuthService.shared.isAuthenticated,
            hasSavedAccount: settings.googleAccount != nil
        )
        if includeGoogleEvents { return events }
        return events.filter { $0.calendarSource != .google }
    }

    /// Credential loss prevents refreshing Google data, but does not imply that its
    /// cached meetings were canceled. Only an explicit disconnect removes the saved
    /// account identity and makes cached Google rows ineligible for alerts.
    nonisolated static func shouldIncludeCachedGoogleEvents(
        isAuthenticated: Bool,
        hasSavedAccount: Bool
    ) -> Bool {
        isAuthenticated || hasSavedAccount
    }

    // MARK: - Private Helpers

    private func googleCalendarInfos(from entries: [GoogleCalendarListEntry]) -> [CalendarInfo] {
        entries.map { entry in
            CalendarInfo(
                id: entry.id,
                name: entry.summary ?? "Unnamed Calendar",
                color: entry.backgroundColor ?? "#4285F4",
                accountName: settings.googleAccount?.email ?? "Google",
                source: .google,
                isSelected: settings.selectedCalendarIds.contains(entry.id),
                isPrimary: entry.primary ?? false
            )
        }
    }

    private func selectedGoogleCalendarIdsForSync() async throws -> [String] {
        let knownGoogleIds = Set(
            availableCalendars
                .filter { $0.source == .google }
                .map(\.id)
        )

        if !knownGoogleIds.isEmpty {
            return settings.selectedCalendarIds.filter { knownGoogleIds.contains($0) }
        }

        guard !settings.selectedCalendarIds.isEmpty else { return [] }

        // Recover from a transient calendar-list failure at launch. Without this
        // retry, every later event sync silently skips all selected Google IDs.
        let entries = try await googleCalendarService.fetchCalendarList()
        let infos = googleCalendarInfos(from: entries)
        availableCalendars.removeAll { $0.source == .google }
        availableCalendars.append(contentsOf: infos)

        let fetchedGoogleIds = Set(infos.map(\.id))
        return settings.selectedCalendarIds.filter { fetchedGoogleIds.contains($0) }
    }

    private func syncGoogleCalendars(timeMin: Date, timeMax: Date) async throws {
        if !GoogleAuthService.shared.isAuthenticated,
           settings.googleAccount != nil {
            // Periodic syncs double as a recovery path after a transient Keychain or
            // credential-read failure. This never opens an interactive sign-in flow.
            await GoogleAuthService.shared.checkAuthenticationStatus()
        }

        guard GoogleAuthService.shared.isAuthenticated else {
            if settings.googleAccount != nil {
                throw SyncError.googleCredentialsUnavailable
            }
            return
        }
        guard let context = modelContext else { return }

        let selectedGoogleCalendarIds = try await selectedGoogleCalendarIdsForSync()
        var firstSyncError: Error?

        for calendarId in selectedGoogleCalendarIds {
            do {
                // Get sync metadata
                let metadata = fetchOrCreateSyncMetadata(for: calendarId, source: .google, context: context)

                let (events, newSyncToken): ([GoogleEvent], String?)

                if let existingSyncToken = metadata.syncToken {
                    // Try incremental sync
                    do {
                        (events, newSyncToken) = try await googleCalendarService.fetchAllEvents(
                            calendarId: calendarId,
                            timeMin: timeMin,
                            timeMax: timeMax,
                            syncToken: existingSyncToken
                        )
                        metadata.lastIncrementalSync = Date()
                    } catch GoogleCalendarService.CalendarAPIError.syncTokenExpired {
                        // Token expired, do full sync
                        (events, newSyncToken) = try await performGoogleFullSync(
                            calendarId: calendarId,
                            timeMin: timeMin,
                            timeMax: timeMax,
                            context: context
                        )
                        metadata.lastFullSync = Date()
                    }
                } else {
                    // Full sync
                    (events, newSyncToken) = try await performGoogleFullSync(
                        calendarId: calendarId,
                        timeMin: timeMin,
                        timeMax: timeMax,
                        context: context
                    )
                    metadata.lastFullSync = Date()
                }

                // Process events
                processGoogleEvents(events, calendarId: calendarId, context: context)

                // Update sync token
                metadata.syncToken = newSyncToken

                try context.save()

            } catch let tokenError as TokenManager.TokenError {
                throw tokenError
            } catch let calendarError as GoogleCalendarService.CalendarAPIError
                where calendarError.requiresReauthentication {
                throw calendarError
            } catch {
                print("Failed to sync Google calendar \(calendarId): \(error)")
                if firstSyncError == nil {
                    firstSyncError = error
                }
            }
        }

        if let firstSyncError {
            throw firstSyncError
        }
    }

    private func performGoogleFullSync(
        calendarId: String,
        timeMin: Date,
        timeMax: Date,
        context: ModelContext
    ) async throws -> ([GoogleEvent], String?) {
        // Fetch first so a network/API failure cannot leave pending deletions that
        // a later context save accidentally commits.
        let result = try await googleCalendarService.fetchAllEvents(
            calendarId: calendarId,
            timeMin: timeMin,
            timeMax: timeMax
        )

        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.calendarId == calendarId && $0.calendarSourceRaw == "google" }
        )
        let existingEvents = (try? context.fetch(descriptor)) ?? []
        existingEvents.forEach { context.delete($0) }

        return result
    }

    private func processGoogleEvents(_ events: [GoogleEvent], calendarId: String, context: ModelContext) {
        for googleEvent in events {
            // Check if event already exists
            let eventId = "g_\(googleEvent.id)"
            let descriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { $0.id == eventId }
            )
            let existingEvents = (try? context.fetch(descriptor)) ?? []

            if googleEvent.status == "cancelled" {
                // Delete cancelled events
                existingEvents.forEach { context.delete($0) }
            } else if let existing = existingEvents.first {
                // Update existing event
                updateCalendarEvent(existing, from: googleEvent)
            } else if let newEvent = createCalendarEvent(from: googleEvent, calendarId: calendarId) {
                // Create new event
                context.insert(newEvent)
            }
        }
    }

    private func syncEventKitCalendars(timeMin: Date, timeMax: Date) async throws {
        guard eventKitService.isAuthorized else { return }
        guard let context = modelContext else { return }

        let selectedEventKitCalendarIds = settings.selectedCalendarIds.filter { id in
            availableCalendars.first { $0.id == id }?.source == .eventKit
        }

        guard !selectedEventKitCalendarIds.isEmpty else { return }

        do {
            let events = try eventKitService.fetchCalendarEvents(
                from: timeMin,
                to: timeMax,
                calendarIds: Array(selectedEventKitCalendarIds)
            )

            // Clear existing EventKit events for selected calendars
            for calendarId in selectedEventKitCalendarIds {
                let descriptor = FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate { $0.calendarId == calendarId && $0.calendarSourceRaw == "eventKit" }
                )
                let existingEvents = (try? context.fetch(descriptor)) ?? []
                existingEvents.forEach { context.delete($0) }
            }

            // Insert new events
            for event in events {
                context.insert(event)
            }

            try context.save()

        } catch {
            print("Failed to sync EventKit calendars: \(error)")
            throw error
        }
    }

    private func fetchOrCreateSyncMetadata(for calendarId: String, source: CalendarSource, context: ModelContext) -> SyncMetadata {
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.calendarId == calendarId }
        )

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let metadata = SyncMetadata(calendarId: calendarId, calendarSource: source)
        context.insert(metadata)
        return metadata
    }

    private func createCalendarEvent(from googleEvent: GoogleEvent, calendarId: String) -> CalendarEvent? {
        guard let start = googleEvent.start,
              let end = googleEvent.end,
              let startDate = start.asDate,
              let endDate = end.asDate else {
            return nil
        }

        let calendarName = availableCalendars.first { $0.id == calendarId }?.name ?? "Google Calendar"

        let event = CalendarEvent(
            id: "g_\(googleEvent.id)",
            title: googleEvent.summary ?? "Untitled Event",
            startDate: startDate,
            endDate: endDate,
            calendarId: calendarId,
            calendarName: calendarName,
            calendarSource: .google
        )

        event.eventDescription = googleEvent.description
        event.location = googleEvent.location
        event.isAllDay = start.isAllDay
        event.organizerEmail = googleEvent.organizer?.email
        event.organizerName = googleEvent.organizer?.displayName
        event.etag = googleEvent.etag

        // Extract meeting link
        event.meetingLink = googleEvent.conferenceData?.entryPoints?
            .first { $0.entryPointType == "video" }?.uri ?? googleEvent.hangoutLink

        return event
    }

    private func updateCalendarEvent(_ event: CalendarEvent, from googleEvent: GoogleEvent) {
        event.title = googleEvent.summary ?? "Untitled Event"
        event.startDate = googleEvent.start?.asDate ?? event.startDate
        event.endDate = googleEvent.end?.asDate ?? event.endDate
        event.eventDescription = googleEvent.description
        event.location = googleEvent.location
        if let start = googleEvent.start {
            event.isAllDay = start.isAllDay
        }
        event.organizerEmail = googleEvent.organizer?.email
        event.organizerName = googleEvent.organizer?.displayName
        event.etag = googleEvent.etag
        event.lastSynced = Date()

        event.meetingLink = googleEvent.conferenceData?.entryPoints?
            .first { $0.entryPointType == "video" }?.uri ?? googleEvent.hangoutLink
    }

    private func refreshUpcomingEvents() {
        upcomingEvents = getUpcomingEvents(within: 24)
    }

    private func cleanOldEvents() {
        guard let context = modelContext else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -pastDays, to: Date())!
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.endDate < cutoffDate }
        )

        if let oldEvents = try? context.fetch(descriptor) {
            oldEvents.forEach { context.delete($0) }
            try? context.save()
        }
    }

    private func setupObservers() {
        // Observe calendar data changes from EventKit
        NotificationCenter.default.publisher(for: .calendarDataChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performSync(force: true)
                }
            }
            .store(in: &cancellables)

        // Observe selected calendar changes
        NotificationCenter.default.publisher(for: .selectedCalendarIdsChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performSync(force: true)
                }
            }
            .store(in: &cancellables)

        // Observe sync interval changes
        NotificationCenter.default.publisher(for: .syncIntervalChanged)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.stopPeriodicSync()
                self?.startPeriodicSync()
            }
            .store(in: &cancellables)
    }
}

extension CalendarSyncManager {
    enum SyncError: Error, LocalizedError {
        case googleCredentialsUnavailable

        var errorDescription: String? {
            switch self {
            case .googleCredentialsUnavailable:
                return "Google Calendar credentials are unavailable"
            }
        }
    }
}
