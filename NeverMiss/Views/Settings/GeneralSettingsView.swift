import SwiftUI
import ServiceManagement
import Sparkle

struct GeneralSettingsView: View {

    // MARK: - Properties

    @Bindable var settings = SettingsManager.shared

    let syncManager = CalendarSyncManager.shared

    @State private var loginItemEnabled = false
    @State private var showResetConfirmation = false

    // MARK: - Body

    var body: some View {
        Form {
            Section(header: Text("Startup")){
                Toggle("Launch at Login", isOn: $loginItemEnabled)
                    .onChange(of: loginItemEnabled) { _, newValue in
                        updateLoginItem(enabled: newValue)
                    }

                Text("NeverMiss will automatically start when you log in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("Calendar Sync")) {
                Picker("Sync Interval", selection: $settings.syncInterval) {
                    Text("Every 5 minutes").tag(5)
                    Text("Every 10 minutes").tag(10)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                }

                HStack {
                    Button {
                        Task { await syncManager.performSync() }
                    } label: {
                        HStack(spacing: 6) {
                            if syncManager.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(syncManager.isSyncing ? "Syncing..." : "Sync Now")
                        }
                    }
                    .disabled(syncManager.isSyncing || !syncManager.canManualSync)

                    if !syncManager.canManualSync {
                        Text("Available in \(syncManager.manualSyncCooldownRemaining) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastSync = settings.lastSyncDate {
                    HStack {
                        Circle()
                            .fill(syncFreshnessColor(lastSync: lastSync))
                            .frame(width: 8, height: 8)
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Updates")) {
                Button("Check for Updates...") {
                    NeverMissApp.updaterController.checkForUpdates(nil)
                }

                Toggle("Automatically check for updates", isOn: Binding(
                    get: { NeverMissApp.updaterController.updater.automaticallyChecksForUpdates },
                    set: { NeverMissApp.updaterController.updater.automaticallyChecksForUpdates = $0 }
                ))
            }

            Section(header: Text("Reset")) {
                Button("Reset All Settings") {
                    showResetConfirmation = true
                }
                .foregroundStyle(.red)

                Text("This will reset all settings to their default values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        .onAppear {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Private Helper Methods

    private func syncFreshnessColor(lastSync: Date) -> Color {
        let elapsed = Date().timeIntervalSince(lastSync)
        let intervalSeconds = TimeInterval(settings.syncInterval * 60)

        if elapsed <= intervalSeconds {
            return .green
        } else if elapsed <= intervalSeconds * 2 {
            return .yellow
        } else {
            return .red
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
            // Revert UI state
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Preview

#Preview {
    GeneralSettingsView()
}
