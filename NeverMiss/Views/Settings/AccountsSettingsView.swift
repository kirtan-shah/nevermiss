import SwiftUI

struct AccountsSettingsView: View {

    // MARK: - Properties

    let authService = GoogleAuthService.shared
    let eventKitService = EventKitService.shared
    let settings = SettingsManager.shared

    @State private var isSigningIn = false
    @State private var signInError: String?

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                statusBorderedContent(isConnected: authService.isAuthenticated) {
                    if authService.isAuthenticated {
                        googleConnectedView
                    } else {
                        googleDisconnectedView
                    }
                }
            } header: {
                Label("Google Calendar", systemImage: "globe")
            }

            Section {
                statusBorderedContent(isConnected: eventKitService.isAuthorized) {
                    if eventKitService.isAuthorized {
                        nativeCalendarConnectedView
                    } else {
                        nativeCalendarDisconnectedView
                    }
                }
            } header: {
                Label("macOS Calendar", systemImage: "calendar")
            }
        }
        .formStyle(.grouped)
        .alert("Sign In Error", isPresented: Binding(
            get: { signInError != nil },
            set: { if !$0 { signInError = nil } }
        )) {
            Button("OK") { signInError = nil }
        } message: {
            if let error = signInError {
                Text(error)
            }
        }
    }

    // MARK: - Subviews

    private var googleConnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)

                if let account = settings.googleAccount {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName ?? account.email)
                            .font(.headline)
                        Text(account.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Connected")
                        .font(.headline)
                }

                Spacer()

                Button("Disconnect") {
                    Task {
                        await authService.signOut()
                    }
                }
                .foregroundStyle(.red)
            }

            Text("Your Google Calendar is connected and syncing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var googleDisconnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)

                Text("Not Connected")
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: signInToGoogle) {
                    if isSigningIn {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Connect")
                    }
                }
                .disabled(isSigningIn)
            }

            Text("Connect your Google Calendar to sync meetings and get reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nativeCalendarConnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)

                Text("Access Granted")
                    .font(.headline)

                Spacer()

                Text("\(eventKitService.calendars.count) calendars")
                    .foregroundStyle(.secondary)
            }

            Text("NeverMiss can access your local calendars.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nativeCalendarDisconnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)

                Text("Access Not Granted")
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Grant Access") {
                    Task {
                        do {
                            _ = try await eventKitService.requestAccess()
                        } catch {
                            signInError = error.localizedDescription
                        }
                    }
                }
            }

            Text("Grant access to use calendars from Apple Calendar, Outlook, and other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusBorderedContent<Content: View>(
        isConnected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 4)

            content()
                .padding(.leading, 12)
        }
    }

    // MARK: - Private Helper Methods

    private func signInToGoogle() {
        isSigningIn = true
        signInError = nil

        Task {
            do {
                try await authService.signIn()
            } catch let error as GoogleAuthService.AuthError {
                if case .userCancelled = error {
                    // User cancelled, don't show error
                } else {
                    signInError = error.localizedDescription
                }
            } catch {
                signInError = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}

// MARK: - Preview

#Preview {
    AccountsSettingsView()
}
