import Foundation

// MARK: - PopupMode

enum PopupMode: String, Codable, CaseIterable, Identifiable {
    case nativeFullScreen = "nativeFullScreen"
    case overlay = "overlay"
    case coverScreen = "coverScreen"
    case banner = "banner"

    // MARK: - Properties

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nativeFullScreen: return "Full Screen"
        case .overlay: return "Dark Overlay"
        case .coverScreen: return "Blur Overlay"
        case .banner: return "Banner"
        }
    }

    var description: String {
        switch self {
        case .nativeFullScreen: return "Enters macOS full screen mode on a new Space"
        case .overlay: return "Dark overlay on top of all windows, including full screen apps"
        case .coverScreen: return "Blurred overlay that covers the screen"
        case .banner: return "Non-intrusive banner at the top of the screen"
        }
    }

    var iconName: String {
        switch self {
        case .nativeFullScreen: return "arrow.up.left.and.arrow.down.right"
        case .overlay: return "square.on.square"
        case .coverScreen: return "rectangle.inset.filled"
        case .banner: return "rectangle.topthird.inset.filled"
        }
    }
}

// MARK: - MultiMonitorOption

enum MultiMonitorOption: String, Codable, CaseIterable, Identifiable {
    case mainScreenOnly = "mainScreenOnly"
    case allScreens = "allScreens"
    case primaryMonitor = "primaryMonitor"

    // MARK: - Properties

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainScreenOnly: return "Main Screen Only"
        case .allScreens: return "All Screens"
        case .primaryMonitor: return "Primary Monitor"
        }
    }

    var description: String {
        switch self {
        case .mainScreenOnly: return "Show alert only on the screen with the active window"
        case .allScreens: return "Show alert on all connected monitors"
        case .primaryMonitor: return "Show alert only on the primary monitor (with menu bar)"
        }
    }
}

// MARK: - AlertTiming

struct AlertTiming: Codable, Identifiable, Hashable {

    // MARK: - Properties

    let id: UUID
    var minutesBefore: Int
    var isEnabled: Bool

    var displayText: String {
        if minutesBefore == 1 {
            return "1 minute before"
        } else {
            return "\(minutesBefore) minutes before"
        }
    }

    var shortDisplayText: String {
        return "\(minutesBefore) min"
    }

    /// Default timing options
    static let defaults: [AlertTiming] = [
        AlertTiming(minutesBefore: 0, isEnabled: true),
        AlertTiming(minutesBefore: 1, isEnabled: true),
        AlertTiming(minutesBefore: 2, isEnabled: true),
        AlertTiming(minutesBefore: 5, isEnabled: true),
        AlertTiming(minutesBefore: 10, isEnabled: false),
        AlertTiming(minutesBefore: 15, isEnabled: false),
        AlertTiming(minutesBefore: 30, isEnabled: false)
    ]

    // MARK: - Initializers

    init(minutesBefore: Int, isEnabled: Bool = true) {
        self.id = UUID()
        self.minutesBefore = minutesBefore
        self.isEnabled = isEnabled
    }
}

// MARK: - SoundSettings

struct SoundSettings: Codable, Equatable {

    // MARK: - Properties

    var isEnabled: Bool
    var soundName: String
    var volume: Float

    static let `default` = SoundSettings(
        isEnabled: true,
        soundName: "Glass",
        volume: 0.7
    )

    /// Available system sounds
    static let availableSounds = [
        "Glass",
        "Ping",
        "Pop",
        "Purr",
        "Sosumi",
        "Submarine",
        "Tink"
    ]
}

// MARK: - CalendarInfo

struct CalendarInfo: Codable, Identifiable, Hashable {

    // MARK: - Properties

    let id: String
    let name: String
    let color: String
    let accountName: String
    let source: CalendarSource
    var isSelected: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CalendarInfo, rhs: CalendarInfo) -> Bool {
        lhs.id == rhs.id
    }
}
