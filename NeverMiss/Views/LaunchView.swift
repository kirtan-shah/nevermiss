import SwiftUI

struct LaunchView: View {

    // MARK: - Properties

    /// Local toggle state -- does NOT write to the observed property directly
    @State private var showMenuBar: Bool
    /// Value at app launch, used to detect pending changes
    private let launchValue: Bool

    init() {
        let current = SettingsManager.shared.showMenuBarIcon
        _showMenuBar = State(initialValue: current)
        launchValue = current
    }

    private var needsRelaunch: Bool {
        showMenuBar != launchValue
    }

    private var numCalendarsConnected: Int8 {
        (GoogleAuthService.shared.isAuthenticated ? 1 : 0)
            + (EventKitService.shared.isAuthorized ? 1 : 0)
    }

    private var nextEvent: CalendarEvent? {
        CalendarSyncManager.shared.upcomingEvents.first
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.nmAccent.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 60
                    ))
                    .frame(width: 100, height: 100)
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.nmAccent)
            }

            Text("NeverMiss")
                .font(.system(size: 26, weight: .bold))

            Text("Never miss a meeting again")
                .font(.subheadline)
                .foregroundStyle(Color.nmTextSecondary)

            statusBadge

            if let event = nextEvent {
                nextMeetingCard(event)
            }

            SettingsLink {
                Label("Open Preferences", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()
                .frame(width: 200)

            Toggle("Show Menu Bar Icon", isOn: $showMenuBar)
                .toggleStyle(.switch)
                .frame(width: 200)
                .onChange(of: showMenuBar) { _, newValue in
                    // Write directly to UserDefaults, bypassing the observed property
                    // so the running MenuBarExtra scene is not disturbed
                    UserDefaults.standard.set(newValue, forKey: "showMenuBarIcon")
                }

            if needsRelaunch {
                Text("Requires relaunch to take effect.")
                    .font(.caption)
                    .foregroundStyle(Color.nmUrgencyHigh)

                Button("Relaunch NeverMiss") {
                    relaunchApp()
                }
                .controlSize(.small)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    private var statusBadge: some View {
        let color: Color = numCalendarsConnected > 0 ? .nmSuccess : .nmUrgencyMedium
        let label = numCalendarsConnected > 0 ? "Running" : "Not Connected"

        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.nmCaption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.nmSuccess.opacity(0.08))
        .clipShape(.capsule)
    }

    private func nextMeetingCard(_ event: CalendarEvent) -> some View {
        let minutesUntil = event.timeUntilStart / 60

        return NMCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("NEXT MEETING")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.nmTextTertiary)
                    Spacer()
                    Text(event.relativeTimeUntilStart)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.urgencyColor(for: minutesUntil))
                }

                Text(event.title)
                    .font(.nmHeadline)
                    .lineLimit(1)

                Text("\(event.formattedStartTime) \u{2022} \(event.calendarName)")
                    .font(.nmCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.nmTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 280)
    }

    // MARK: - Private Helper Methods

    private func relaunchApp() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && open \"\(appURL.path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Preview

#Preview {
    LaunchView()
}
