import SwiftUI
import SwiftData
import Sparkle

// MARK: - NeverMissApp

@main
struct NeverMissApp: App {

    // MARK: - Properties

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private let modelContainer: ModelContainer

    @Bindable var settings = SettingsManager.shared
    let syncManager = CalendarSyncManager.shared
    let appState = AppState.shared
    let authService = GoogleAuthService.shared
    let scheduler = MeetingScheduler.shared

    // MARK: - Initializers

    init() {
        do {
            let schema = Schema([
                CalendarEvent.self,
                SyncMetadata.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            let container = modelContainer
            Task { @MainActor in
                CalendarSyncManager.shared.configure(with: container.mainContext)
            }
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }

    // MARK: - Body

    var body: some Scene {
        // Menu bar icon (toggleable from launch window)
        MenuBarExtra(isInserted: $settings.showMenuBarIcon) {
            MenuBarView()
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        .windowResizability(.automatic)

        // Keeps the app alive when MenuBarExtra is hidden
        Window("", id: "keepalive") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
    }

    // MARK: - Private Helpers

    private var menuBarLabel: some View {
        Image("MenuBarIcon")
            .accessibilityLabel("NeverMiss")
    }
}
