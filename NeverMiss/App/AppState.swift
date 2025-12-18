import SwiftUI

// MARK: - AppState

/// Central app state manager
@Observable
@MainActor
final class AppState {

    // MARK: - Properties

    static let shared = AppState()

    @ObservationIgnored let settings = SettingsManager.shared
    @ObservationIgnored let syncManager = CalendarSyncManager.shared
    @ObservationIgnored let scheduler = MeetingScheduler.shared
    @ObservationIgnored let authService = GoogleAuthService.shared
    @ObservationIgnored let eventKitService = EventKitService.shared

    var isReady = false

    var isConnectedToAnyCalendar: Bool {
        authService.isAuthenticated || eventKitService.isAuthorized
    }

    var nextMeeting: CalendarEvent? {
        syncManager.upcomingEvents.first
    }

    var timeUntilNextMeeting: TimeInterval? {
        nextMeeting?.timeUntilStart
    }

    // MARK: - Initializers

    private init() {
        setupInitialState()
    }

    // MARK: - Actions

    func connectGoogleCalendar() async throws {
        try await authService.signIn()
        await syncManager.refreshCalendarList()
        await syncManager.performSync()
    }

    func disconnectGoogleCalendar() async {
        await authService.signOut()
        await syncManager.refreshCalendarList()
    }

    func requestCalendarAccess() async throws -> Bool {
        let granted = try await eventKitService.requestAccess()
        if granted {
            await syncManager.refreshCalendarList()
            await syncManager.performSync()
        }
        return granted
    }

    func refresh() async {
        await syncManager.performSync()
    }

    // MARK: - Private Helpers

    private func setupInitialState() {
        Task {
            // Check authentication status
            await authService.checkAuthenticationStatus()

            // Refresh calendar list
            await syncManager.refreshCalendarList()

            isReady = true
        }
    }
}
