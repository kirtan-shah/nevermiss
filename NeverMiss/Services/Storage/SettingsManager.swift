import AppKit
import SwiftUI

// MARK: - Type Definition

@Observable
@MainActor
final class SettingsManager {

    // MARK: - Static Properties

    static let shared = SettingsManager()

    // MARK: - Setting Keys

    private enum SettingKey: String, CaseIterable {
        case alertTimings, popupMode, multiMonitorOption, soundSettings
        case keyboardShortcutsEnabled, selectedCalendarIds, launchAtLogin
        case syncInterval, showMenuBarIcon, hasCompletedOnboarding
        case lastSyncDate, googleAccount, appearance

        var defaultValue: Any? {
            switch self {
                case .alertTimings:             return try? JSONEncoder().encode(AlertTiming.defaults)
                case .popupMode:                return PopupMode.coverScreen.rawValue
                case .multiMonitorOption:       return MultiMonitorOption.allScreens.rawValue
                case .soundSettings:            return try? JSONEncoder().encode(SoundSettings.default)
                case .keyboardShortcutsEnabled: return false
                case .selectedCalendarIds:      return [String]()
                case .launchAtLogin:            return false
                case .syncInterval:             return 5
                case .showMenuBarIcon:          return true
                case .hasCompletedOnboarding:   return false
                case .lastSyncDate:             return nil
                case .googleAccount:            return nil
                case .appearance:               return AppearancePreference.system.rawValue
            }
        }
    }

    // MARK: - Properties

    var alertTimings: [AlertTiming] {
        didSet { encode(alertTimings, for: .alertTimings) }
    }

    var popupMode: PopupMode {
        didSet { defaults.set(popupMode.rawValue, forKey: SettingKey.popupMode.rawValue) }
    }

    var multiMonitorOption: MultiMonitorOption {
        didSet { defaults.set(multiMonitorOption.rawValue, forKey: SettingKey.multiMonitorOption.rawValue) }
    }

    var soundSettings: SoundSettings {
        didSet { encode(soundSettings, for: .soundSettings) }
    }

    var keyboardShortcutsEnabled: Bool {
        didSet { defaults.set(keyboardShortcutsEnabled, forKey: SettingKey.keyboardShortcutsEnabled.rawValue) }
    }

    var selectedCalendarIds: Set<String> {
        didSet {
            defaults.set(Array(selectedCalendarIds), forKey: SettingKey.selectedCalendarIds.rawValue)
            if selectedCalendarIds != oldValue {
                NotificationCenter.default.post(name: .selectedCalendarIdsChanged, object: nil)
            }
        }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: SettingKey.launchAtLogin.rawValue) }
    }

    var syncInterval: Int {
        didSet {
            defaults.set(syncInterval, forKey: SettingKey.syncInterval.rawValue)
            if syncInterval != oldValue {
                NotificationCenter.default.post(name: .syncIntervalChanged, object: nil)
            }
        }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: SettingKey.showMenuBarIcon.rawValue) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: SettingKey.hasCompletedOnboarding.rawValue) }
    }

    var lastSyncDate: Date? {
        didSet {
            if let date = lastSyncDate {
                defaults.set(date, forKey: SettingKey.lastSyncDate.rawValue)
            } else {
                defaults.removeObject(forKey: SettingKey.lastSyncDate.rawValue)
            }
        }
    }

    var googleAccount: GoogleAccount? {
        didSet { encode(googleAccount, for: .googleAccount) }
    }

    var appearance: AppearancePreference {
        didSet {
            defaults.set(appearance.rawValue, forKey: SettingKey.appearance.rawValue)
            applyAppearance()
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: - Initialization

    private init() {
        let registrationDict = SettingKey.allCases.reduce(into: [String: Any]()) { dict, key in
            if let value = key.defaultValue {
                dict[key.rawValue] = value
            }
        }
        defaults.register(defaults: registrationDict)

        self.alertTimings = Self.decode(.alertTimings, from: defaults)!
        self.popupMode = PopupMode(rawValue: defaults.string(forKey: SettingKey.popupMode.rawValue)!)!
        self.multiMonitorOption = MultiMonitorOption(rawValue: defaults.string(forKey: SettingKey.multiMonitorOption.rawValue)!)!
        self.soundSettings = Self.decode(.soundSettings, from: defaults)!
        self.keyboardShortcutsEnabled = defaults.bool(forKey: SettingKey.keyboardShortcutsEnabled.rawValue)
        self.selectedCalendarIds = Set(defaults.stringArray(forKey: SettingKey.selectedCalendarIds.rawValue)!)
        self.launchAtLogin = defaults.bool(forKey: SettingKey.launchAtLogin.rawValue)
        self.syncInterval = defaults.integer(forKey: SettingKey.syncInterval.rawValue)
        self.showMenuBarIcon = defaults.bool(forKey: SettingKey.showMenuBarIcon.rawValue)
        self.hasCompletedOnboarding = defaults.bool(forKey: SettingKey.hasCompletedOnboarding.rawValue)
        self.lastSyncDate = defaults.object(forKey: SettingKey.lastSyncDate.rawValue) as? Date
        self.googleAccount = Self.decode(.googleAccount, from: defaults)
        self.appearance = AppearancePreference(
            rawValue: defaults.string(forKey: SettingKey.appearance.rawValue)!
        )!
        // Do NOT call applyAppearance() here — NSApp isn't initialized yet.
        // AppDelegate.applicationDidFinishLaunching calls it once NSApp is live.
    }

    // MARK: - Theme

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Computed Properties

    var enabledAlertTimings: [AlertTiming] {
        alertTimings.filter { $0.isEnabled }
    }

    var enabledAlertMinutes: [Int] {
        enabledAlertTimings.map { $0.minutesBefore }.sorted(by: >)
    }

    var isGoogleConnected: Bool {
        googleAccount?.isConnected ?? false
    }

    // MARK: - Actions/Methods

    func resetToDefaults() {
        self.alertTimings = decode(.alertTimings)!
        self.popupMode = PopupMode(rawValue: defaults.string(forKey: SettingKey.popupMode.rawValue)!)!
        self.multiMonitorOption = MultiMonitorOption(rawValue: defaults.string(forKey: SettingKey.multiMonitorOption.rawValue)!)!
        self.soundSettings = decode(.soundSettings)!
        self.keyboardShortcutsEnabled = defaults.bool(forKey: SettingKey.keyboardShortcutsEnabled.rawValue)
        self.selectedCalendarIds = Set(defaults.stringArray(forKey: SettingKey.selectedCalendarIds.rawValue)!)
        self.launchAtLogin = defaults.bool(forKey: SettingKey.launchAtLogin.rawValue)
        self.syncInterval = defaults.integer(forKey: SettingKey.syncInterval.rawValue)
    }

    func updateAlertTiming(_ timing: AlertTiming) {
        if let index = alertTimings.firstIndex(where: { $0.id == timing.id }) {
            alertTimings[index] = timing
        }
    }

    func toggleCalendarSelection(_ calendarId: String) {
        if selectedCalendarIds.contains(calendarId) {
            selectedCalendarIds.remove(calendarId)
        } else {
            selectedCalendarIds.insert(calendarId)
        }
    }

    func selectCalendars(_ calendarIds: [String]) {
        selectedCalendarIds.formUnion(calendarIds)
    }

    func deselectCalendars(_ calendarIds: [String]) {
        selectedCalendarIds.subtract(calendarIds)
    }

    func disconnectGoogleAccount() {
        googleAccount = nil
    }

    // MARK: - Private Helpers

    private func encode<T: Encodable>(_ value: T?, for key: SettingKey) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    private func decode<T: Decodable>(_ key: SettingKey) -> T? {
        Self.decode(key, from: defaults)
    }

    private static func decode<T: Decodable>(_ key: SettingKey, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let selectedCalendarIdsChanged = Notification.Name("selectedCalendarIdsChanged")
    static let syncIntervalChanged = Notification.Name("syncIntervalChanged")
}
