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
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            Text("NeverMiss")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)

            Text("Never miss a meeting again")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)

            if !needsRelaunch {
                statusBadge

                if let event = nextEvent {
                    nextMeetingCard(event)
                }

                SettingsLink {
                    Label("Open Preferences", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Divider()
                .frame(width: 200)
                .overlay(.white.opacity(0.3))

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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45))
                    .clipShape(.capsule)

                Button("Relaunch NeverMiss") {
                    relaunchApp()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: needsRelaunch)
        .background(alignment: .center) {
            Image("Background")
                .resizable()
                .scaledToFill()
                .frame(width: 460, height: 540)
        }
        .clipped()
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
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45))
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
