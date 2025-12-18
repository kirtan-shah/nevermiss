import SwiftUI

struct BannerAlertView: View {

    // MARK: - Properties

    let event: CalendarEvent
    let timing: AlertTiming
    let onJoin: () -> Void
    let onSnooze: (Date) -> Void
    let onDismiss: () -> Void

    @State private var appearAnimation = false
    @State private var isHovered = false
    @State private var autoDismissProgress: CGFloat = 1.0

    private var urgencyColor: Color {
        Color.urgencyColor(for: event.timeUntilStart)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressBar

            HStack(spacing: NMSpacing.md) {
                urgencyDot
                meetingInfo
                Spacer(minLength: 0)
                actionButtons
            }
            .padding(.horizontal, NMSpacing.lg)
            .padding(.vertical, NMSpacing.md)
        }
        .background(bannerBackground)
        .overlay(
            RoundedRectangle(cornerRadius: NMSpacing.radiusLg)
                .stroke(Color.nmSeparator, lineWidth: 1)
        )
        .clipShape(.rect(
            topLeadingRadius: 0,
            bottomLeadingRadius: NMSpacing.radiusLg,
            bottomTrailingRadius: NMSpacing.radiusLg,
            topTrailingRadius: 0
        ))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .offset(y: appearAnimation ? 0 : -20)
        .opacity(appearAnimation ? 1 : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appearAnimation = true
            }
            withAnimation(.linear(duration: 30)) {
                autoDismissProgress = 0
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(30))
            onDismiss()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting reminder for \(event.title)")
    }

    // MARK: - Subviews

    private var progressBar: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(urgencyColor)
                .frame(width: geometry.size.width * autoDismissProgress, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var urgencyDot: some View {
        Circle()
            .fill(urgencyColor)
            .frame(width: 8, height: 8)
            .modifier(PulsingModifier())
            .accessibilityHidden(true)
    }

    private var meetingInfo: some View {
        VStack(alignment: .leading, spacing: NMSpacing.xxs) {
            Text(event.title)
                .font(.nmBodyMedium)
                .foregroundStyle(Color.nmTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: NMSpacing.sm) {
                Text(timeText)
                    .font(.nmCaptionMedium)
                    .foregroundStyle(urgencyColor)

                if event.meetingLink != nil {
                    Text(meetingPlatform)
                        .font(.nmCaption)
                        .foregroundStyle(Color.nmAccent)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: NMSpacing.sm) {
            if event.meetingLink != nil {
                Button(action: onJoin) {
                    Text("Join")
                        .font(.nmCaptionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.nmAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join meeting")
            }

            if let next = MeetingScheduler.shared.nextAlert(for: event.id) {
                Button {
                    onSnooze(next.scheduledTime)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.nmTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.nmSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snooze until next alert")
            } else {
                Menu {
                    ForEach(1...5, id: \.self) { minutes in
                        Button("\(minutes) minute\(minutes == 1 ? "" : "s")") {
                            onSnooze(Date().addingTimeInterval(Double(minutes * 60)))
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.nmTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.nmSurface)
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .accessibilityLabel("Snooze meeting reminder")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Color.nmTextSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.nmSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss meeting reminder")
        }
    }

    private var bannerBackground: some View {
        ZStack {
            Color.nmSurface.opacity(0.95)
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    // MARK: - Private Helper Methods

    private var timeText: String {
        let seconds = Int(event.timeUntilStart)
        if seconds <= 0 {
            return "Starting now"
        } else if seconds < 60 {
            return "in \(seconds)s"
        } else {
            return "in \(seconds / 60)m"
        }
    }

    private var meetingPlatform: String {
        guard let link = event.meetingLink?.lowercased() else { return "Video" }

        if link.contains("zoom") { return "Zoom" }
        if link.contains("meet.google") { return "Meet" }
        if link.contains("teams") { return "Teams" }
        return "Video"
    }
}

// MARK: - Supporting Types

private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Preview

#Preview {
    let event = {
        let e = CalendarEvent(
            id: "preview",
            title: "Weekly Team Sync",
            startDate: Date().addingTimeInterval(120),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            calendarName: "Work",
            calendarSource: .google
        )
        e.meetingLink = "https://zoom.us/j/123456789"
        return e
    }()

    VStack {
        BannerAlertView(
            event: event,
            timing: AlertTiming(minutesBefore: 2),
            onJoin: {},
            onSnooze: { _ in },
            onDismiss: {}
        )
        .frame(width: 420)
        Spacer()
    }
    .background(Color.gray.opacity(0.3))
}
