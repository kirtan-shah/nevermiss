import SwiftUI

struct AlertWrapperView: View {

    // MARK: - Properties

    let event: CalendarEvent
    let timing: AlertTiming
    let popupMode: PopupMode
    let onJoin: () -> Void
    let onSnooze: (Date) -> Void
    let onDismiss: () -> Void

    private var urgencyColor: Color {
        Color.urgencyColor(for: event.timeUntilStart)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Button(action: onDismiss) {
                background
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss alert")

            AlertContentView(
                event: event,
                timing: timing,
                onJoin: onJoin,
                onSnooze: onSnooze,
                onDismiss: onDismiss
            )
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var background: some View {
        switch popupMode {
        case .overlay:
            Color.black.opacity(0.85)
                .ignoresSafeArea()

        case .coverScreen, .nativeFullScreen:
            ZStack {
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [urgencyColor.opacity(0.12), .clear],
                    center: .top,
                    startRadius: 50,
                    endRadius: 500
                )
                .ignoresSafeArea()
            }

        case .banner:
            Color.clear
        }
    }
}

// MARK: - Preview

#Preview("Cover Screen") {
    let event = CalendarEvent(
        id: "preview",
        title: "Team Standup Meeting",
        startDate: Date().addingTimeInterval(300),
        endDate: Date().addingTimeInterval(3600),
        calendarId: "primary",
        calendarName: "Work",
        calendarSource: .google
    )
    event.meetingLink = "https://meet.google.com/abc-defg-hij"
    event.location = "Conference Room A"

    return AlertWrapperView(
        event: event,
        timing: AlertTiming(minutesBefore: 5),
        popupMode: .coverScreen,
        onJoin: {},
        onSnooze: { _ in },
        onDismiss: {}
    )
}

#Preview("Overlay") {
    let event = CalendarEvent(
        id: "preview",
        title: "Team Standup Meeting",
        startDate: Date().addingTimeInterval(300),
        endDate: Date().addingTimeInterval(3600),
        calendarId: "primary",
        calendarName: "Work",
        calendarSource: .google
    )
    event.meetingLink = "https://meet.google.com/abc-defg-hij"

    return AlertWrapperView(
        event: event,
        timing: AlertTiming(minutesBefore: 5),
        popupMode: .overlay,
        onJoin: {},
        onSnooze: { _ in },
        onDismiss: {}
    )
}
