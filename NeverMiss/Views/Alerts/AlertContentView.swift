import SwiftUI


struct AlertContentView: View {

    // MARK: - Properties

    let event: CalendarEvent
    let timing: AlertTiming
    let onJoin: () -> Void
    let onSnooze: (Date) -> Void
    let onDismiss: () -> Void
    let settings = SettingsManager.shared

    @State private var appearAnimation = false
    @State private var showSnoozeOptions = false
    @State private var showSkipConfirmation = false
    @Bindable private var alertController = AlertWindowController.shared

    /// Total countdown duration in seconds (used to compute ring progress)
    private var totalDuration: Double {
        Double(timing.minutesBefore * 60)
    }

    private var nextScheduledAlert: ScheduledAlert? {
        MeetingScheduler.shared.nextAlert(for: event.id)
    }

    private var isLastAlert: Bool {
        nextScheduledAlert == nil
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let countdown = max(0, Int(event.timeUntilStart))
            let progress = totalDuration > 0 ? Double(countdown) / totalDuration : 0
            let urgency = Color.urgencyColor(for: event.timeUntilStart)

            VStack(spacing: NMSpacing.xxl) {
                countdownRing(countdown: countdown, progress: progress, urgency: urgency)
                meetingDetails
                platformBadge
                actionButtons(countdown: countdown)

                if settings.keyboardShortcutsEnabled {
                    keyboardHints
                }
            }
            .frame(maxWidth: 600)
            .padding(NMSpacing.xxxl)
            .background(
                RoundedRectangle(cornerRadius: NMSpacing.radiusXl)
                    .fill(Color.nmBackground.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: NMSpacing.radiusXl)
                            .fill(.thinMaterial)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
        }
        .offset(y: appearAnimation ? 0 : 20)
        .opacity(appearAnimation ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                appearAnimation = true
            }
        }
        .onChange(of: alertController.skipRequested) {
            if alertController.skipRequested {
                alertController.skipRequested = false
                showSkipConfirmation = true
            }
        }
        .onChange(of: alertController.snoozeRequested) {
            if alertController.snoozeRequested {
                alertController.snoozeRequested = false
                if let next = nextScheduledAlert {
                    onSnooze(next.scheduledTime)
                } else {
                    showSnoozeOptions = true
                }
            }
        }
    }

    // MARK: - Subviews

    private var meetingDetails: some View {
        VStack(spacing: NMSpacing.sm) {
            Text(event.title)
                .font(.nmDisplayLarge)
                .foregroundStyle(Color.nmTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: NMSpacing.sm) {
                Image(systemName: "clock.fill")
                Text(event.formattedStartTime)
            }
            .font(.nmMono)
            .foregroundStyle(Color.nmTextSecondary)

            if let location = event.location, !location.isEmpty {
                HStack(spacing: NMSpacing.sm) {
                    Image(systemName: "location.fill")
                    Text(location)
                        .lineLimit(1)
                }
                .font(.nmCaption)
                .foregroundStyle(Color.nmTextTertiary)
            }
        }
    }

    @ViewBuilder
    private var platformBadge: some View {
        if let link = event.meetingLink {
            let platform = MeetingURLParser.identifyPlatform(from: link)
            NMBadge(icon: "video.fill", text: platform.rawValue, color: .nmAccent)
        }
    }

    private var keyboardHints: some View {
        HStack(spacing: NMSpacing.xl) {
            ForEach(AlertKeyBinding.allCases, id: \.self) { binding in
                NMKeyboardHint(key: binding.label, action: binding.action)
            }
        }
    }

    private func countdownRing(countdown: Int, progress: Double, urgency: Color) -> some View {
        NMProgressRing(progress: progress, color: urgency, size: 120, lineWidth: 4)
            .overlay {
                Text(countdownText(for: countdown))
                    .font(.system(size: countdown < 60 ? 36 : 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(urgency)
            }
            .phaseAnimator(
                [1.0, 1.05],
                trigger: countdown
            ) { content, phase in
                content.scaleEffect(countdown < 30 ? phase : 1.0)
            }
            .animation(.easeInOut(duration: 0.3), value: progress)
    }

    private func actionButtons(countdown: Int) -> some View {
        let hasMeetingLink = event.meetingLink != nil
        let showGlow = countdown < 60 && hasMeetingLink

        return VStack(spacing: NMSpacing.lg) {
            if hasMeetingLink {
                Button(action: onJoin) {
                    HStack(spacing: NMSpacing.md) {
                        Image(systemName: "video.fill")
                        Text("Join Meeting")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.nmAccent)
                    .clipShape(.rect(cornerRadius: NMSpacing.radiusLg))
                }
                .buttonStyle(.plain)
                .phaseAnimator(
                    [false, true],
                    trigger: countdown < 60
                ) { content, phase in
                    content.shadow(
                        color: showGlow
                            ? Color.nmAccent.opacity(phase ? 0.3 : 0.1) : .clear,
                        radius: phase ? 16 : 8
                    )
                }
                .accessibilityLabel("Join Meeting")
            } else {
                Button {
                    showSkipConfirmation = true
                } label: {
                    HStack(spacing: NMSpacing.md) {
                        Image(systemName: "checkmark")
                        Text("OK, Got It")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.nmDismissText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.nmDismiss)
                    .clipShape(.rect(cornerRadius: NMSpacing.radiusLg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("OK, Got It")
            }

            HStack(spacing: NMSpacing.md) {
                if let next = nextScheduledAlert {
                    // More alerts coming — single tap snooze to next alert time
                    Button {
                        onSnooze(next.scheduledTime)
                    } label: {
                        HStack(spacing: NMSpacing.sm) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Snooze → \(next.scheduledTime.formatted(date: .omitted, time: .shortened))")
                        }
                        .font(.nmHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.nmSnooze)
                        .clipShape(.rect(cornerRadius: NMSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Snooze until \(next.scheduledTime.formatted(date: .omitted, time: .shortened))")
                } else {
                    // Last alert — popover with 1-5 minute options
                    Button {
                        showSnoozeOptions = true
                    } label: {
                        HStack(spacing: NMSpacing.sm) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Snooze")
                        }
                        .font(.nmHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.nmSnooze)
                        .clipShape(.rect(cornerRadius: NMSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSnoozeOptions) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach((1...5).reversed(), id: \.self) { minutes in
                                Button {
                                    showSnoozeOptions = false
                                    onSnooze(Date().addingTimeInterval(Double(minutes * 60)))
                                } label: {
                                    Text("\(minutes) minute\(minutes == 1 ? "" : "s")")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(width: 140)
                    }
                    .accessibilityLabel("Snooze meeting reminder")
                }

                if hasMeetingLink {
                    Button {
                        showSkipConfirmation = true
                    } label: {
                        HStack(spacing: NMSpacing.sm) {
                            Image(systemName: "forward.fill")
                            Text("Skip")
                        }
                        .font(.nmHeadline)
                        .foregroundStyle(Color.nmDismissText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.nmDismiss)
                        .clipShape(.rect(cornerRadius: NMSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip meeting")
                }
            }
        }
        .alert("Skip this meeting?", isPresented: $showSkipConfirmation) {
            Button("Skip", role: .destructive, action: onDismiss)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will not be reminded for \(event.title).")
        }
    }

    // MARK: - Private Helper Methods

    private func countdownText(for countdown: Int) -> String {
        if countdown <= 0 {
            return "NOW"
        } else if countdown < 60 {
            return "\(countdown)"
        } else {
            let minutes = countdown / 60
            let seconds = countdown % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}


// MARK: - Supporting Types

enum AlertKeyBinding: CaseIterable {
    case join
    case snooze
    case skip

    var keyCode: UInt16 {
        switch self {
        case .join:   return 36  // Return
        case .snooze: return 53  // Escape
        case .skip:   return 51  // Delete/Backspace
        }
    }

    var label: String {
        switch self {
        case .join:   return "enter"
        case .snooze: return "esc"
        case .skip:   return "delete"
        }
    }

    var action: String {
        switch self {
        case .join:   return "Join"
        case .snooze: return "Snooze"
        case .skip:   return "Skip"
        }
    }

    static func from(keyCode: UInt16) -> AlertKeyBinding? {
        allCases.first { $0.keyCode == keyCode }
    }
}

// MARK: - Preview

#Preview("Meeting in 2 min") {
    let _ = SettingsManager.shared.keyboardShortcutsEnabled = true
    let startDate = Date().addingTimeInterval(120)
    let event: CalendarEvent = {
        let e = CalendarEvent(
            id: "preview-1",
            title: "Team Standup",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            calendarId: "primary",
            calendarName: "Work",
            calendarSource: .google
        )
        e.meetingLink = "https://meet.google.com/abc-defg-hij"
        e.location = "Conference Room A"
        return e
    }()

    // Simulate a 1-min alert still scheduled so the inline snooze shows
    let _ = MeetingScheduler.shared.scheduledAlerts.append(
        ScheduledAlert(
            id: "preview-1_1",
            eventId: "preview-1",
            eventTitle: "Team Standup",
            meetingLink: event.meetingLink,
            scheduledTime: startDate.addingTimeInterval(-60),
            minutesBefore: 1
        )
    )

    AlertContentView(
        event: event,
        timing: AlertTiming(minutesBefore: 2),
        onJoin: {},
        onSnooze: { _ in },
        onDismiss: {}
    )
    .frame(width: 600, height: 600)
    .background(Color.black.opacity(0.9))
}

#Preview("Meeting NOW") {
    let _ = SettingsManager.shared.keyboardShortcutsEnabled = true
    let event: CalendarEvent = {
        let e = CalendarEvent(
            id: "preview-2",
            title: "Design Review: Q2 Roadmap",
            startDate: Date().addingTimeInterval(15),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "primary",
            calendarName: "Design",
            calendarSource: .google
        )
        e.meetingLink = "https://zoom.us/j/123456789"
        return e
    }()

    AlertContentView(
        event: event,
        timing: AlertTiming(minutesBefore: 1),
        onJoin: {},
        onSnooze: { _ in },
        onDismiss: {}
    )
    .frame(width: 600, height: 600)
    .background(Color.black.opacity(0.9))
}

#Preview("No meeting link") {
    let event = CalendarEvent(
        id: "preview-3",
        title: "Lunch with Sarah",
        startDate: Date().addingTimeInterval(600),
        endDate: Date().addingTimeInterval(4200),
        calendarId: "personal",
        calendarName: "Personal",
        calendarSource: .eventKit
    )

    AlertContentView(
        event: event,
        timing: AlertTiming(minutesBefore: 10),
        onJoin: {},
        onSnooze: { _ in },
        onDismiss: {}
    )
    .frame(width: 600, height: 500)
    .background(Color.black.opacity(0.9))
}
