import SwiftUI

struct SettingsView: View {

    // MARK: - Properties

    @State private var selectedTab = SettingsTab.general

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gear", value: .general) {
                GeneralSettingsView()
                    .settingsTabFrame()
            }

            Tab("Alerts", systemImage: "bell.badge", value: .alerts) {
                AlertSettingsView()
                    .settingsTabFrame()
            }
            
            Tab("Calendars", systemImage: "calendar", value: .calendars) {
                CalendarSelectionView()
                    .settingsTabFrame()
                
            }
            
            Tab("Accounts", systemImage: "person.crop.circle", value: .accounts) {
                AccountsSettingsView()
                    .settingsTabFrame()
            }
        }
    }
}

// MARK: - Supporting Types

private extension View {
    func settingsTabFrame() -> some View {
        self.frame(width: 560, height: 440)
    }
}

enum SettingsTab: Hashable {
    case general
    case accounts
    case alerts
    case calendars
}

// MARK: - Preview

#Preview {
    SettingsView()
}
