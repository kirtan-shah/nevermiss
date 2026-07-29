//
//  NeverMissTests.swift
//  NeverMissTests
//
//  Created by Kirtan Shah on 12/17/25.
//

import Foundation
import Testing
@testable import NeverMiss

@Suite(.serialized)
struct NeverMissTests {

    @Test func unitTestsUseInMemoryKeychain() async {
        #expect(await KeychainService.shared.usesInMemoryStoreForTesting())
    }

    @MainActor
    @Test func ongoingMeetingCanBeSnoozedRepeatedlyAcrossResyncs() async throws {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let startDate = now.addingTimeInterval(-60)
        let event = makeEvent(
            id: "snooze-ongoing",
            title: "Standup",
            startDate: startDate,
            endDate: now.addingTimeInterval(3600)
        )

        scheduler.rescheduleAlerts(for: [event])
        #expect(scheduler.currentAlert?.event.id == event.id)
        scheduler.snoozeCurrentAlert(until: Date().addingTimeInterval(0.3))

        let refreshedEvent = makeEvent(
            id: event.id,
            title: "Standup (refreshed)",
            startDate: startDate,
            endDate: event.endDate
        )

        scheduler.rescheduleAlerts(for: [refreshedEvent])

        #expect(scheduler.currentAlert == nil)
        #expect(scheduler.pendingAlerts.isEmpty)
        #expect(scheduler.scheduledAlerts.isEmpty)
        #expect(scheduler.isSnoozedForTesting(eventId: event.id))

        try await Task.sleep(for: .milliseconds(450))
        #expect(scheduler.currentAlert?.event.title == refreshedEvent.title)

        scheduler.snoozeCurrentAlert(until: Date().addingTimeInterval(0.3))
        scheduler.rescheduleAlerts(for: [refreshedEvent])
        #expect(scheduler.currentAlert == nil)

        try await Task.sleep(for: .milliseconds(450))
        #expect(scheduler.currentAlert?.event.id == event.id)
    }

    @MainActor
    @Test func secondSnoozeReplacesExistingSnoozeTimer() async throws {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let event = makeEvent(
            id: "snooze-replace",
            title: "Review",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(4200)
        )

        scheduler.currentAlert = AlertContext(event: event, timing: AlertTiming(minutesBefore: 10))
        scheduler.snoozeCurrentAlert(until: now.addingTimeInterval(0.2))

        scheduler.currentAlert = AlertContext(event: event, timing: AlertTiming(minutesBefore: 10))
        scheduler.snoozeCurrentAlert(until: now.addingTimeInterval(0.55))

        try await Task.sleep(for: .milliseconds(350))
        #expect(scheduler.currentAlert == nil)

        try await Task.sleep(for: .milliseconds(350))
        #expect(scheduler.currentAlert?.event.id == event.id)
    }

    @MainActor
    @Test func ongoingSnoozeSurvivesEventLeavingUpcomingSet() async throws {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let event = makeEvent(
            id: "snooze-past-event-end",
            title: "Short meeting",
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(0.1)
        )

        scheduler.rescheduleAlerts(for: [event])
        scheduler.snoozeCurrentAlert(until: now.addingTimeInterval(0.3))

        // Models the next upcoming-events refresh after the meeting has ended.
        scheduler.rescheduleAlerts(for: [])
        #expect(scheduler.isSnoozedForTesting(eventId: event.id))

        try await Task.sleep(for: .milliseconds(450))
        #expect(scheduler.currentAlert?.event.id == event.id)

        // The fired alert remains actionable even while the source event is absent.
        scheduler.rescheduleAlerts(for: [])
        #expect(scheduler.currentAlert?.event.id == event.id)

        scheduler.snoozeCurrentAlert(until: Date().addingTimeInterval(0.3))
        scheduler.rescheduleAlerts(for: [])

        try await Task.sleep(for: .milliseconds(450))
        #expect(scheduler.currentAlert?.event.id == event.id)
    }

    @MainActor
    @Test func dismissedOccurrenceRejectsStaleTimerCallbacks() {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let event = makeEvent(
            id: "dismissed-stale-callback",
            title: "Planning",
            startDate: now.addingTimeInterval(-30),
            endDate: now.addingTimeInterval(1800)
        )

        scheduler.rescheduleAlerts(for: [event])
        scheduler.cancelAlerts(for: event)
        scheduler.dismissCurrentAlert(eventId: event.id)

        // A sync that returns the same occurrence must not resurrect it after Join/Skip.
        scheduler.rescheduleAlerts(for: [event])
        #expect(scheduler.currentAlert == nil)
        #expect(scheduler.pendingAlerts.isEmpty)

        // Models a timer task that was queued before cancellation completed.
        scheduler.attemptToShowAlertForTesting(event: event)
        #expect(scheduler.currentAlert == nil)
        #expect(scheduler.pendingAlerts.isEmpty)
    }

    @MainActor
    @Test func removingCurrentEventDoesNotHideNextQueuedAlert() {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let first = makeEvent(
            id: "current-removed",
            title: "First",
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(1800)
        )
        let second = makeEvent(
            id: "next-queued",
            title: "Second",
            startDate: now.addingTimeInterval(-30),
            endDate: now.addingTimeInterval(1800)
        )

        scheduler.rescheduleAlerts(for: [first])
        scheduler.rescheduleAlerts(for: [first, second])
        #expect(scheduler.currentAlert?.event.id == first.id)
        #expect(scheduler.pendingAlerts.contains { $0.event.id == second.id })

        scheduler.rescheduleAlerts(for: [second])

        // The old window is still logically current until its dismissal completes.
        #expect(scheduler.currentAlert?.event.id == first.id)
        scheduler.dismissCurrentAlert(eventId: first.id, startDate: first.startDate)
        #expect(scheduler.currentAlert?.event.id == second.id)
    }

    @MainActor
    @Test func dismissedOccurrenceSurvivesMissingSyncSnapshot() {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let event = makeEvent(
            id: "dismissed-across-missing-sync",
            title: "Planning",
            startDate: now.addingTimeInterval(-30),
            endDate: now.addingTimeInterval(1800)
        )

        scheduler.rescheduleAlerts(for: [event])
        scheduler.cancelAlerts(for: event)
        scheduler.dismissCurrentAlert(eventId: event.id, startDate: event.startDate)

        scheduler.rescheduleAlerts(for: [])
        scheduler.rescheduleAlerts(for: [event])

        #expect(scheduler.currentAlert == nil)
        #expect(scheduler.pendingAlerts.isEmpty)
    }

    @MainActor
    @Test func rescheduledOccurrenceWaitsForVisibleWindowToDismiss() {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let original = makeEvent(
            id: "rescheduled-current",
            title: "Original time",
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(1800)
        )
        let moved = makeEvent(
            id: original.id,
            title: "Updated time",
            startDate: now.addingTimeInterval(-30),
            endDate: now.addingTimeInterval(1830)
        )

        scheduler.rescheduleAlerts(for: [original])
        scheduler.rescheduleAlerts(for: [moved])

        #expect(scheduler.currentAlert?.event.startDate == original.startDate)
        #expect(scheduler.pendingAlerts.contains {
            $0.event.id == moved.id && $0.event.startDate == moved.startDate
        })

        scheduler.dismissCurrentAlert(eventId: original.id, startDate: original.startDate)
        #expect(scheduler.currentAlert?.event.startDate == moved.startDate)
    }

    @MainActor
    @Test func snoozedPendingAlertSurvivesLeavingUpcomingSet() async throws {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let snoozed = makeEvent(
            id: "snoozed-behind-current",
            title: "Snoozed",
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(60)
        )
        let blocker = makeEvent(
            id: "blocking-alert",
            title: "Blocking",
            startDate: now.addingTimeInterval(-30),
            endDate: now.addingTimeInterval(1800)
        )

        scheduler.rescheduleAlerts(for: [snoozed])
        scheduler.snoozeCurrentAlert(until: Date().addingTimeInterval(0.3))
        scheduler.rescheduleAlerts(for: [snoozed, blocker])

        try await Task.sleep(for: .milliseconds(450))
        #expect(scheduler.currentAlert?.event.id == blocker.id)
        #expect(scheduler.pendingAlerts.contains { $0.event.id == snoozed.id })

        scheduler.rescheduleAlerts(for: [blocker])
        #expect(scheduler.pendingAlerts.contains { $0.event.id == snoozed.id })

        scheduler.cancelAlerts(for: blocker)
        scheduler.dismissCurrentAlert(eventId: blocker.id, startDate: blocker.startDate)
        #expect(scheduler.currentAlert?.event.id == snoozed.id)
    }

    @MainActor
    @Test func changedStartTimeCancelsOldOccurrenceSnooze() {
        let scheduler = MeetingScheduler.shared
        scheduler.resetStateForTesting()
        defer { scheduler.resetStateForTesting() }

        let now = Date()
        let event = makeEvent(
            id: "rescheduled-snooze",
            title: "One-on-one",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(2400)
        )

        scheduler.rescheduleAlerts(for: [event])
        scheduler.currentAlert = AlertContext(event: event, timing: AlertTiming(minutesBefore: 10))
        scheduler.snoozeCurrentAlert(until: now.addingTimeInterval(2))
        #expect(scheduler.isSnoozedForTesting(eventId: event.id))

        let movedEvent = makeEvent(
            id: event.id,
            title: event.title,
            startDate: now.addingTimeInterval(1200),
            endDate: now.addingTimeInterval(3000)
        )

        scheduler.rescheduleAlerts(for: [movedEvent])
        #expect(!scheduler.isSnoozedForTesting(eventId: event.id))
        #expect(scheduler.currentAlert == nil)
    }

    @Test func incrementalGoogleSyncUsesCompatibleQueryParameters() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let url = GoogleCalendarService.makeEventsURL(
            baseURL: "https://www.googleapis.com/calendar/v3",
            calendarId: "primary",
            timeMin: date,
            timeMax: date.addingTimeInterval(3600),
            syncToken: "next-token"
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let names = Set(items.map(\.name))

        #expect(names.contains("syncToken"))
        #expect(!names.contains("orderBy"))
        #expect(!names.contains("timeMin"))
        #expect(!names.contains("timeMax"))
    }

    @Test func fullGoogleSyncKeepsOrderingAndTimeWindow() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let url = GoogleCalendarService.makeEventsURL(
            baseURL: "https://www.googleapis.com/calendar/v3",
            calendarId: "primary",
            timeMin: date,
            timeMax: date.addingTimeInterval(3600)
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let names = Set(items.map(\.name))

        #expect(names.contains("orderBy"))
        #expect(names.contains("timeMin"))
        #expect(names.contains("timeMax"))
        #expect(!names.contains("syncToken"))
    }

    @Test func googleCalendarListRequestsEveryPageToken() throws {
        let firstURL = GoogleCalendarService.makeCalendarListURL(
            baseURL: "https://www.googleapis.com/calendar/v3"
        )
        let nextURL = GoogleCalendarService.makeCalendarListURL(
            baseURL: "https://www.googleapis.com/calendar/v3",
            pageToken: "page-2"
        )
        let firstItems = try #require(
            URLComponents(url: firstURL, resolvingAgainstBaseURL: false)?.queryItems
        )
        let nextItems = try #require(
            URLComponents(url: nextURL, resolvingAgainstBaseURL: false)?.queryItems
        )

        #expect(firstItems.contains { $0.name == "maxResults" && $0.value == "250" })
        #expect(!firstItems.contains { $0.name == "pageToken" })
        #expect(nextItems.contains { $0.name == "pageToken" && $0.value == "page-2" })
    }

    @Test func eventKitIdentifierSurvivesLocalIdentifierChanges() {
        let first = EventKitService.stableEventIdentifier(
            calendarIdentifier: "work",
            externalIdentifier: "server-event",
            eventIdentifier: "local-before-sync",
            occurrenceDate: nil
        )
        let afterSync = EventKitService.stableEventIdentifier(
            calendarIdentifier: "work",
            externalIdentifier: "server-event",
            eventIdentifier: "local-after-sync",
            occurrenceDate: nil
        )
        let firstOccurrence = EventKitService.stableEventIdentifier(
            calendarIdentifier: "work",
            externalIdentifier: "recurring-event",
            eventIdentifier: "local-1",
            occurrenceDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let secondOccurrence = EventKitService.stableEventIdentifier(
            calendarIdentifier: "work",
            externalIdentifier: "recurring-event",
            eventIdentifier: "local-2",
            occurrenceDate: Date(timeIntervalSince1970: 1_700_086_400)
        )

        #expect(first == afterSync)
        #expect(firstOccurrence != secondOccurrence)
    }

    @Test func cancelledGoogleEventTombstoneDecodesWithoutDates() throws {
        let json = #"{"kind":"calendar#events","etag":"list-tag","items":[{"id":"deleted-id","status":"cancelled"}]}"#
        let response = try JSONDecoder().decode(GoogleEventsListResponse.self, from: Data(json.utf8))
        let event = try #require(response.items?.first)

        #expect(event.id == "deleted-id")
        #expect(event.status == "cancelled")
        #expect(event.start?.isAllDay == nil)
        #expect(event.end?.isAllDay == nil)
    }

    @Test func googleDateTimeParsesFractionalSeconds() {
        let dateTime = GoogleEventDateTime(
            date: nil,
            dateTime: "2026-07-28T18:01:02.345-07:00",
            timeZone: "America/Los_Angeles"
        )

        #expect(dateTime.asDate != nil)
    }

    @Test func onlyDefinitiveCredentialFailuresRequireReconnect() {
        #expect(TokenManager.TokenError.tokenExpired.requiresReauthentication)
        #expect(TokenManager.TokenError.noRefreshToken.requiresReauthentication)
        #expect(!TokenManager.TokenError.refreshFailed("HTTP 500").requiresReauthentication)
        #expect(!TokenManager.TokenError.networkError(URLError(.notConnectedToInternet)).requiresReauthentication)

        #expect(GoogleAuthService.AuthError.userInfoUnauthorized.requiresReauthentication)
        #expect(!GoogleAuthService.AuthError.networkError(URLError(.timedOut)).requiresReauthentication)

        #expect(GoogleCalendarService.CalendarAPIError.unauthorized.requiresReauthentication)
        #expect(GoogleCalendarService.CalendarAPIError.insufficientPermissions.requiresReauthentication)
        #expect(!GoogleCalendarService.CalendarAPIError.forbidden.requiresReauthentication)
        #expect(!GoogleCalendarService.CalendarAPIError.rateLimited.requiresReauthentication)
    }

    @Test func cachedGoogleEventsRemainEligibleUntilExplicitDisconnect() {
        #expect(CalendarSyncManager.shouldIncludeCachedGoogleEvents(
            isAuthenticated: true,
            hasSavedAccount: true
        ))
        #expect(CalendarSyncManager.shouldIncludeCachedGoogleEvents(
            isAuthenticated: false,
            hasSavedAccount: true
        ))
        #expect(!CalendarSyncManager.shouldIncludeCachedGoogleEvents(
            isAuthenticated: false,
            hasSavedAccount: false
        ))
    }

    @Test func oauthRefreshRequiresReconnectOnlyForInvalidGrant() {
        let invalidGrant = TokenManager.classifyRefreshFailure(
            statusCode: 400,
            data: Data(#"{"error":"invalid_grant","error_description":"Token revoked"}"#.utf8)
        )
        let invalidClient = TokenManager.classifyRefreshFailure(
            statusCode: 401,
            data: Data(#"{"error":"invalid_client","error_description":"Client rejected"}"#.utf8)
        )
        let malformedResponse = TokenManager.classifyRefreshFailure(
            statusCode: 400,
            data: Data("not-json".utf8)
        )

        #expect(invalidGrant.requiresReauthentication)
        #expect(!invalidClient.requiresReauthentication)
        #expect(!malformedResponse.requiresReauthentication)
    }

    @Test func calendar403DistinguishesMissingScopeFromUsageLimits() {
        let missingScope = GoogleCalendarService.classifyForbiddenResponse(
            Data(#"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#.utf8)
        )
        let quotaFailure = GoogleCalendarService.classifyForbiddenResponse(
            Data(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}"#.utf8)
        )
        let calendarACLFailure = GoogleCalendarService.classifyForbiddenResponse(
            Data(#"{"error":{"errors":[{"reason":"forbidden"}]}}"#.utf8)
        )
        let modernMissingScope = GoogleCalendarService.classifyForbiddenResponse(
            Data(#"{"error":{"details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}"#.utf8)
        )

        #expect(missingScope.requiresReauthentication)
        #expect(modernMissingScope.requiresReauthentication)
        #expect(!quotaFailure.requiresReauthentication)
        #expect(!calendarACLFailure.requiresReauthentication)

        if case .rateLimited = quotaFailure {
            // Expected: retry later without disconnecting the account.
        } else {
            Issue.record("A quota-related 403 should be classified as rate limited")
        }
    }

    private func makeEvent(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            calendarId: "primary",
            calendarName: "Work",
            calendarSource: .google
        )
    }

}
