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

    /// Sync window: 7 days past to 30 days future
    @ObservationIgnored private let pastDays: Int = 7
    @ObservationIgnored private let futureDays: Int = 30

    // MARK: - Initialization

    private init() {
        setupObservers()
    }

    // MARK: - Actions/Methods

    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    func startPeriodicSync() {
        // Initial sync
        Task {
            await performSync()
        }

        // Schedule periodic sync
        let interval = TimeInterval(settings.syncInterval * 60)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performSync()
            }
        }
        RunLoop.main.add(syncTimer!, forMode: .common)
    }

    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil

        defer {
            isSyncing = false
        }

        let now = Date()
        let timeMin = Calendar.current.date(byAdding: .day, value: -pastDays, to: now)!
        let timeMax = Calendar.current.date(byAdding: .day, value: futureDays, to: now)!

        // Sync from both sources concurrently
        async let googleSync: Void = syncGoogleCalendars(timeMin: timeMin, timeMax: timeMax)
        async let eventKitSync: Void = syncEventKitCalendars(timeMin: timeMin, timeMax: timeMax)

        do {
            try await googleSync
            try await eventKitSync
            lastSyncDate = now
            settings.lastSyncDate = now

            // Refresh upcoming events
            refreshUpcomingEvents()

            // Schedule alerts for upcoming events
            await MeetingScheduler.shared.rescheduleAlerts(for: upcomingEvents)

            // Clean old events
            cleanOldEvents()

        } catch {
            syncError = error
            print("Sync error: \(error)")
        }
    }

    func refreshCalendarList() async {
        var calendars: [CalendarInfo] = []

        // Get Google calendars
        if settings.isGoogleConnected {
            do {
                let googleCalendars = try await googleCalendarService.fetchCalendarList()
                calendars.append(contentsOf: googleCalendars.map { entry in
                    CalendarInfo(
                        id: entry.id,
                        name: entry.summary ?? "Unnamed Calendar",
                        color: entry.backgroundColor ?? "#4285F4",
                        accountName: settings.googleAccount?.email ?? "Google",
                        source: .google,
                        isSelected: settings.selectedCalendarIds.contains(entry.id)
                    )
                })
            } catch {
                print("Failed to fetch Google calendars: \(error)")
            }
        }

        // Get EventKit calendars
        if eventKitService.isAuthorized {
            let ekCalendars = eventKitService.getCalendarInfoList()
            calendars.append(contentsOf: ekCalendars.map { info in
                var mutableInfo = info
                mutableInfo.isSelected = settings.selectedCalendarIds.contains(info.id)
                return mutableInfo
            })
        }

        availableCalendars = calendars

        // Auto-select primary calendars if none selected
        if settings.selectedCalendarIds.isEmpty {
            let primaryIds = calendars
                .filter { $0.name.lowercased().contains("primary") || $0.name == settings.googleAccount?.email }
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

        let predicate = #Predicate<CalendarEvent> { event in
            event.startDate >= now && event.startDate <= endDate && !event.isAllDay
        }

        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Private Helpers

    private func syncGoogleCalendars(timeMin: Date, timeMax: Date) async throws {
        guard settings.isGoogleConnected else { return }
        guard let context = modelContext else { return }

        let selectedGoogleCalendarIds = settings.selectedCalendarIds.filter { id in
            availableCalendars.first { $0.id == id }?.source == .google
        }

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

            } catch {
                print("Failed to sync Google calendar \(calendarId): \(error)")
            }
        }
    }

    private func performGoogleFullSync(
        calendarId: String,
        timeMin: Date,
        timeMax: Date,
        context: ModelContext
    ) async throws -> ([GoogleEvent], String?) {
        // Clear existing events for this calendar
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.calendarId == calendarId && $0.calendarSourceRaw == "google" }
        )
        let existingEvents = (try? context.fetch(descriptor)) ?? []
        existingEvents.forEach { context.delete($0) }

        return try await googleCalendarService.fetchAllEvents(
            calendarId: calendarId,
            timeMin: timeMin,
            timeMax: timeMax
        )
    }

    private func processGoogleEvents(_ events: [GoogleEvent], calendarId: String, context: ModelContext) {
        for googleEvent in events {
            // Check if event already exists
            let eventId = googleEvent.id
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
            } else {
                // Create new event
                let newEvent = createCalendarEvent(from: googleEvent, calendarId: calendarId)
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

    private func createCalendarEvent(from googleEvent: GoogleEvent, calendarId: String) -> CalendarEvent {
        let calendarName = availableCalendars.first { $0.id == calendarId }?.name ?? "Google Calendar"

        let event = CalendarEvent(
            id: googleEvent.id,
            title: googleEvent.summary ?? "Untitled Event",
            startDate: googleEvent.start.asDate ?? Date(),
            endDate: googleEvent.end.asDate ?? Date(),
            calendarId: calendarId,
            calendarName: calendarName,
            calendarSource: .google
        )

        event.eventDescription = googleEvent.description
        event.location = googleEvent.location
        event.isAllDay = googleEvent.start.isAllDay
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
        event.startDate = googleEvent.start.asDate ?? event.startDate
        event.endDate = googleEvent.end.asDate ?? event.endDate
        event.eventDescription = googleEvent.description
        event.location = googleEvent.location
        event.isAllDay = googleEvent.start.isAllDay
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
                    await self?.performSync()
                }
            }
            .store(in: &cancellables)

        // Observe selected calendar changes
        NotificationCenter.default.publisher(for: .selectedCalendarIdsChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performSync()
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
