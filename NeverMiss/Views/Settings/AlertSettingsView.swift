import SwiftUI

struct AlertSettingsView: View {

    // MARK: - Properties

    @Bindable var settings = SettingsManager.shared

    // MARK: - Body

    var body: some View {
        Form {
            alertModeSection
            displaySection
            timingSection
            soundSection
            keyboardSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Subviews

    private var alertModeSection: some View {
        Section {
            HStack(spacing: 8) {
                modeCard(for: PopupMode.coverScreen)
                modeCard(for: PopupMode.overlay)
                modeCard(for: PopupMode.banner)
                modeCard(for: PopupMode.nativeFullScreen)
            }
            .animation(.spring(response: 0.3), value: settings.popupMode)

            Text(settings.popupMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Preview This Mode") {
                previewAlert()
            }
            .buttonStyle(.bordered)
        } header: {
            Text("Alert Mode")
        }
    }

    private func modeCard(for mode: PopupMode) -> some View {
        let isSelected = settings.popupMode == mode
        return Button {
            settings.popupMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 20))
                Text(mode.displayName)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var displaySection: some View {
        Section {
            Picker("Show alerts on", selection: $settings.multiMonitorOption) {
                ForEach(MultiMonitorOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Text(settings.multiMonitorOption.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Display")
        }
    }

    private var timingSection: some View {
        Section {
            AlertTimingTimeline(settings: settings)

            Text("Tap to toggle when to receive reminders")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Alert Timing")
        }
    }

    private var soundSection: some View {
        Section {
            Toggle("Play Sound", isOn: $settings.soundSettings.isEnabled)

            if settings.soundSettings.isEnabled {
                HStack {
                    Picker("Sound", selection: $settings.soundSettings.soundName) {
                        ForEach(SoundSettings.availableSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }

                    Button {
                        playTestSound()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Image(systemName: volumeIconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Slider(
                        value: $settings.soundSettings.volume,
                        in: 0...1
                    )
                }
            }
        } header: {
            Text("Sound")
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("Enable Keyboard Shortcuts", isOn: $settings.keyboardShortcutsEnabled)

            Text("When enabled, use Return to join, S to snooze, and Escape to dismiss alerts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Keyboard Shortcuts")
        }
    }

    // MARK: - Private Helper Methods

    private var volumeIconName: String {
        let volume = settings.soundSettings.volume
        if volume <= 0 { return "speaker.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func playTestSound() {
        let soundName = settings.soundSettings.soundName
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.volume = settings.soundSettings.volume
            sound.play()
        }
    }

    private func previewAlert() {
        let sampleEvent = CalendarEvent(
            id: "preview-\(UUID().uuidString)",
            title: "Sample Meeting",
            startDate: Date().addingTimeInterval(120),
            endDate: Date().addingTimeInterval(3600),
            calendarId: "preview",
            calendarName: "Preview Calendar",
            calendarSource: .google
        )
        sampleEvent.meetingLink = "https://meet.google.com/abc-defg-hij"
        sampleEvent.location = "Conference Room A"

        AlertWindowController.shared.showAlert(
            for: sampleEvent,
            timing: AlertTiming(minutesBefore: 2)
        )
    }
}

// MARK: - Supporting Types

private struct AlertTimingTimeline: View {
    @Bindable var settings: SettingsManager

    private let timingMinutes = [1, 2, 5, 10, 15, 30]

    var body: some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 2)

            HStack {
                ForEach(timingMinutes, id: \.self) { minutes in
                    if minutes != timingMinutes.first {
                        Spacer()
                    }

                    timingDot(for: minutes)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func timingDot(for minutes: Int) -> some View {
        let timingIndex = settings.alertTimings.firstIndex { $0.minutesBefore == minutes }
        let isEnabled = timingIndex.map { settings.alertTimings[$0].isEnabled } ?? false

        return Button {
            guard let index = timingIndex else { return }
            var timing = settings.alertTimings[index]
            timing.isEnabled = !timing.isEnabled
            settings.updateAlertTiming(timing)
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(isEnabled ? Color.accentColor : Color(.controlBackgroundColor))
                    .stroke(
                        isEnabled ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: 2
                    )
                    .frame(width: 14, height: 14)
                    .shadow(
                        color: isEnabled ? Color.accentColor.opacity(0.4) : .clear,
                        radius: 4
                    )

                Text("\(minutes)m")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    AlertSettingsView()
}
