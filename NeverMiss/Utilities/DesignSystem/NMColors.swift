import SwiftUI

// MARK: - NeverMiss Color Palette

extension Color {
    // MARK: Backgrounds
    static let nmBackground = Color(red: 0.102, green: 0.102, blue: 0.118)       // #1A1A1E
    static let nmSurface = Color(red: 0.141, green: 0.141, blue: 0.157)           // #242428
    static let nmSurfaceHover = Color(red: 0.180, green: 0.180, blue: 0.204)      // #2E2E34

    // MARK: Text
    static let nmTextPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)       // #F5F5F7
    static let nmTextSecondary = Color(red: 0.557, green: 0.557, blue: 0.576)     // #8E8E93
    static let nmTextTertiary = Color(red: 0.388, green: 0.388, blue: 0.400)      // #636366

    // MARK: Brand
    static let nmAccent = Color(red: 0.369, green: 0.620, blue: 1.0)              // #5E9EFF

    // MARK: Urgency
    static let nmUrgencyCritical = Color(red: 1.0, green: 0.271, blue: 0.227)     // #FF453A
    static let nmUrgencyHigh = Color(red: 1.0, green: 0.624, blue: 0.039)         // #FF9F0A
    static let nmUrgencyMedium = Color(red: 1.0, green: 0.839, blue: 0.039)       // #FFD60A
    static let nmUrgencyLow = Color(red: 0.188, green: 0.820, blue: 0.345)        // #30D158

    // MARK: Actions
    static let nmSnooze = Color(red: 0.749, green: 0.545, blue: 0.243)            // #BF8B3E
    static let nmDismiss = Color(red: 0.282, green: 0.282, blue: 0.290)           // #48484A

    // MARK: Utility
    static let nmSeparator = Color(red: 0.220, green: 0.220, blue: 0.227)         // #38383A
    static let nmSuccess = Color(red: 0.188, green: 0.820, blue: 0.345)           // #30D158

    // MARK: - Hex Initializer

    /// Initialize a Color from a hex string (e.g., "#FF453A" or "FF453A")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    // MARK: - Urgency Color Helper

    /// Returns the appropriate urgency color for a given number of seconds until start
    static func urgencyColor(for secondsUntilStart: TimeInterval) -> Color {
        if secondsUntilStart <= 60 { return .nmUrgencyCritical }
        if secondsUntilStart <= 300 { return .nmUrgencyHigh }
        if secondsUntilStart <= 900 { return .nmUrgencyMedium }
        return .nmUrgencyLow
    }
}
