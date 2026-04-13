import SwiftUI
import ServiceManagement

struct OnboardingView: View {

    // MARK: - Properties

    let authService = GoogleAuthService.shared
    let eventKitService = EventKitService.shared
    @Bindable var settings = SettingsManager.shared

    @State private var currentStep = 0
    @State private var signInError: String?

    @Environment(\.dismiss) private var dismiss

    private var hasCalendarConnected: Bool {
        authService.isAuthenticated || eventKitService.isAuthorized
    }

    private var totalSteps: Int {
        hasCalendarConnected ? 5 : 4
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 40, height: 3)
                }
            }
            .padding(.top, 12)
            .animation(.spring(response: 0.3), value: currentStep)
            .animation(.spring(response: 0.3), value: totalSteps)

            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: appearanceStep
                case 2: connectCalendarsStep
                case 3 where hasCalendarConnected: selectCalendarsStep
                case 3: completeStep
                case 4: completeStep
                default: welcomeStep
                }
            }
        }
        .frame(width: 540, height: 520)
        .alert("Error", isPresented: .constant(signInError != nil)) {
            Button("OK") { signInError = nil }
        } message: {
            if let error = signInError {
                Text(error)
            }
        }
    }

    // MARK: - Subviews

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)

            VStack(spacing: 8) {
                Text("Never miss a meeting")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)

                Text("Intelligent reminders that keep you on time, every time.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
            }

            VStack(spacing: 8) {
                featureRow(icon: "bell.badge.fill", color: .red, text: "Full-screen alerts you can't miss")
                featureRow(icon: "calendar", color: .blue, text: "Syncs with Google Calendar & macOS Calendar")
                featureRow(icon: "video.fill", color: .green, text: "One-click meeting join")
            }
            .padding(.horizontal, 32)


            Button("Get Started") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    currentStep = 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Image("Background")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .clipped()
    }

    private var connectCalendarsStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Connect Your Calendars")
                .font(.title2.bold())

            Text("Connect at least one calendar source to get started.\nYou can always add or change these later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                connectionCard(
                    title: "Google Calendar",
                    description: "Sync meetings from Google",
                    icon: "globe",
                    iconColor: .blue,
                    isConnected: authService.isAuthenticated,
                    action: connectGoogle
                )

                connectionCard(
                    title: "macOS Calendar",
                    description: "Apple Calendar, Outlook, etc.",
                    icon: "calendar",
                    iconColor: .red,
                    isConnected: eventKitService.isAuthorized,
                    action: connectEventKit
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button("Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = 1
                    }
                }

                Button("Continue") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = 3
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private var selectCalendarsStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Select Your Calendars")
                    .font(.title2.bold())

                Text("Choose which calendars to get reminders for.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            CalendarSelectionView()
                .frame(maxHeight: .infinity)

            HStack(spacing: 16) {
                Button("Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = 2
                    }
                }

                Button("Continue") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = 4
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
    }

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if hasCalendarConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, options: .nonRepeating)
                
                VStack(spacing: 8) {
                    Text("You're All Set!")
                        .font(.title.bold())
                    
                    Text("NeverMiss will now remind you before your meetings")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, options: .nonRepeating)
                
                VStack(spacing: 8) {
                    Text("No Calendars Connected")
                        .font(.title.bold())
                    
                    Text("NeverMiss will not be able to remind you before your meetings")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

            }

            VStack(spacing: 8) {
                tipRow("Look for the calendar icon in your menu bar")
                tipRow("Click it to see upcoming meetings")
                tipRow("Customize alerts in Settings")
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button("Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = hasCalendarConnected ? 3 : 2
                    }
                }
                Button("Start Using NeverMiss") {
                    updateLoginItem(enabled: true)
                    settings.hasCompletedOnboarding = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }

    private var appearanceStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "paintpalette.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Choose your look")
                    .font(.title.bold())

                Text("Pick a theme now — you can always change it later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 64)

            Spacer()

            HStack(spacing: 16) {
                Button("Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = 0
                    }
                }

                Button("Continue") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentStep = 2
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            Spacer()
        }
        .padding()
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(.rect(cornerRadius: 8))

            Text(text)
                .font(.body)
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(12)
        .background(.black.opacity(0.35))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func tipRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .frame(width: 24)

            Text(text)
                .font(.body)

            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func connectionCard(
        title: String,
        description: String,
        icon: String,
        iconColor: Color,
        isConnected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(iconColor)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("Connect", action: action)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Private Helper Methods

    private func connectGoogle() {
        Task {
            do {
                try await authService.signIn()
            } catch let error as GoogleAuthService.AuthError {
                if case .userCancelled = error { } else {
                    signInError = error.localizedDescription
                }
            } catch {
                signInError = error.localizedDescription
            }
        }
    }

    private func connectEventKit() {
        Task {
            do {
                _ = try await eventKitService.requestAccess()
            } catch {
                signInError = error.localizedDescription
            }
            // Bring our window back to front after system permission dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.title == "NeverMiss" }?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
