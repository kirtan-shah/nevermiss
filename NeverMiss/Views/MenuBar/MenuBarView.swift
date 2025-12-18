import SwiftUI

struct MenuBarView: View {

    // MARK: - Properties

    let syncManager = CalendarSyncManager.shared
    let authService = GoogleAuthService.shared
    let settings = SettingsManager.shared

    @State private var hoveredEventID: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, NMSpacing.lg)
                .frame(height: 48)

            Color.nmSeparator.frame(height: 1)

            if !authService.isAuthenticated && !EventKitService.shared.isAuthorized {
                notConnectedView
            } else if syncManager.upcomingEvents.isEmpty {
                noEventsView
            } else {
                eventListView
            }

            Color.nmSeparator.frame(height: 1)

            footerView
                .padding(.horizontal, NMSpacing.lg)
                .frame(height: 40)
        }
        .frame(width: 340)
        .background(Color.nmBackground)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            if let nextEvent = syncManager.upcomingEvents.first {
                HStack(spacing: NMSpacing.xs) {
                    Text("Next in")
                        .font(.nmCaption)
                        .foregroundStyle(Color.nmTextSecondary)

                    Text(nextEvent.relativeTimeUntilStart)
                        .font(.nmMonoMedium)
                        .foregroundStyle(Color.nmTextPrimary)
                }
            } else {
                Text("All clear")
                    .font(.nmMonoMedium)
                    .foregroundStyle(Color.nmTextSecondary)
            }

            Spacer()
        }
        .overlay(alignment: .top) {
            if let nextEvent = syncManager.upcomingEvents.first,
               nextEvent.timeUntilStart < 900 {
                RadialGradient(
                    colors: [
                        Color.urgencyColor(for: nextEvent.timeUntilStart).opacity(0.06),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 120
                )
                .frame(height: 48)
                .allowsHitTesting(false)
            }
        }
    }

    private var notConnectedView: some View {
        VStack(spacing: NMSpacing.lg) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundStyle(Color.nmTextSecondary)

            VStack(spacing: NMSpacing.sm) {
                Text("No Calendar Connected")
                    .font(.nmHeadline)
                    .foregroundStyle(Color.nmTextPrimary)

                Text("Connect your Google Calendar or enable local calendar access to get meeting reminders.")
                    .font(.nmCaption)
                    .foregroundStyle(Color.nmTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsLink {
                Text("Open Settings")
                    .font(.nmBodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, NMSpacing.lg)
                    .padding(.vertical, NMSpacing.sm)
                    .background(Color.nmAccent)
                    .clipShape(Capsule())
            }
        }
        .padding(NMSpacing.xl)
    }

    private var noEventsView: some View {
        VStack(spacing: NMSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.nmSuccess)

            Text("You're free")
                .font(.nmHeadline)
                .foregroundStyle(Color.nmTextPrimary)

            Text("No meetings in the next 24 hours")
                .font(.nmCaption)
                .foregroundStyle(Color.nmTextSecondary)

            if let lastSync = syncManager.lastSyncDate {
                Text("Last synced \(lastSync, style: .relative) ago")
                    .font(.nmCaption)
                    .foregroundStyle(Color.nmTextTertiary)
            }
        }
        .padding(NMSpacing.xl)
    }

    private var eventListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let grouped = groupedEvents
                ForEach(grouped, id: \.label) { section in
                    sectionHeader(section.label)

                    ForEach(section.events) { event in
                        UpcomingMeetingRow(
                            event: event,
                            isHovered: hoveredEventID == event.id,
                            onHover: { hovering in
                                hoveredEventID = hovering ? event.id : nil
                            }
                        )
                        .padding(.horizontal, NMSpacing.sm)
                        .padding(.vertical, NMSpacing.xxs)
                    }
                }
            }
            .padding(.vertical, NMSpacing.sm)
        }
        .frame(maxHeight: 360)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.nmCaptionMedium)
            .tracking(1.2)
            .foregroundStyle(Color.nmTextTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NMSpacing.lg)
            .padding(.top, NMSpacing.md)
            .padding(.bottom, NMSpacing.xs)
    }

    private var footerView: some View {
        HStack(spacing: 0) {
            SettingsLink {
                HStack(spacing: NMSpacing.xs) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.nmCaption)
                .foregroundStyle(Color.nmTextTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: NMSpacing.xs) {
                if let lastSync = syncManager.lastSyncDate {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.nmCaption)
                        .foregroundStyle(Color.nmTextTertiary)
                }

                Button {
                    Task { await syncManager.performSync() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.nmTextTertiary)
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(syncManager.isSyncing ? 360 : 0))
                        .animation(
                            syncManager.isSyncing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: syncManager.isSyncing
                        )
                }
                .buttonStyle(.plain)
                .disabled(syncManager.isSyncing)
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.nmCaption)
                    .foregroundStyle(Color.nmTextTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Private Helper Methods

    private var groupedEvents: [EventSection] {
        let events = Array(syncManager.upcomingEvents.prefix(10))
        let now = Date()
        let calendar = Calendar.current

        var ongoing: [CalendarEvent] = []
        var nextHour: [CalendarEvent] = []
        var laterToday: [CalendarEvent] = []
        var tomorrow: [CalendarEvent] = []

        let oneHourFromNow = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let endOfToday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)

        for event in events {
            if event.isOngoing {
                ongoing.append(event)
            } else if event.startDate < oneHourFromNow {
                nextHour.append(event)
            } else if event.startDate < endOfToday {
                laterToday.append(event)
            } else {
                tomorrow.append(event)
            }
        }

        var sections: [EventSection] = []
        if !ongoing.isEmpty { sections.append(EventSection(label: "Now", events: ongoing)) }
        if !nextHour.isEmpty { sections.append(EventSection(label: "Next Hour", events: nextHour)) }
        if !laterToday.isEmpty { sections.append(EventSection(label: "Later Today", events: laterToday)) }
        if !tomorrow.isEmpty { sections.append(EventSection(label: "Tomorrow", events: tomorrow)) }
        return sections
    }
}

// MARK: - Supporting Types

private struct EventSection: Identifiable {
    let label: String
    let events: [CalendarEvent]
    var id: String { label }
}

struct UpcomingMeetingRow: View {

    // MARK: - Properties

    let event: CalendarEvent
    let isHovered: Bool
    let onHover: (Bool) -> Void

    private var urgencyColor: Color {
        Color.urgencyColor(for: event.timeUntilStart)
    }

    private var relativeTimeText: String {
        if event.isOngoing { return "now" }
        let minutes = Int(event.timeUntilStart / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "in \(hours)h" }
        return "in \(hours)h\(remainingMinutes)m"
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Urgency bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(urgencyColor)
                .frame(width: 3, height: 36)
                .padding(.trailing, NMSpacing.sm)

            // Time column
            VStack(alignment: .trailing, spacing: NMSpacing.xxs) {
                Text(event.formattedStartTime)
                    .font(.nmMono)
                    .foregroundStyle(Color.nmTextPrimary)

                Text(relativeTimeText)
                    .font(.nmCaption)
                    .foregroundStyle(Color.nmTextTertiary)
            }
            .frame(width: 56, alignment: .trailing)
            .padding(.trailing, NMSpacing.md)

            // Center content
            VStack(alignment: .leading, spacing: NMSpacing.xxs) {
                Text(event.title)
                    .font(.nmBodyMedium)
                    .foregroundStyle(Color.nmTextPrimary)
                    .lineLimit(1)

                HStack(spacing: NMSpacing.sm) {
                    Text(event.calendarName)
                        .font(.nmCaption)
                        .foregroundStyle(Color.nmTextTertiary)

                    if event.meetingLink != nil {
                        videoPlatformBadge
                    }
                }
            }

            Spacer(minLength: NMSpacing.sm)

            // Join button
            if let link = event.meetingLink, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("Join")
                        .font(.nmCaptionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, NMSpacing.md)
                        .padding(.vertical, NMSpacing.xs)
                        .background(Color.nmAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NMSpacing.sm)
        .padding(.vertical, NMSpacing.sm)
        .background(isHovered ? Color.nmSurfaceHover : Color.nmSurface)
        .clipShape(.rect(cornerRadius: NMSpacing.radiusMd))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            onHover(hovering)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    private var videoPlatformBadge: some View {
        Text(platformName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.nmAccent)
            .padding(.horizontal, NMSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.nmAccent.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Private Helper Methods

    private var platformName: String {
        guard let link = event.meetingLink else { return "Video" }
        let platform = MeetingURLParser.identifyPlatform(from: link)
        switch platform {
        case .googleMeet: return "Meet"
        case .microsoftTeams: return "Teams"
        case .gotoMeeting: return "GoTo"
        case .unknown: return "Video"
        default: return platform.rawValue
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
}
