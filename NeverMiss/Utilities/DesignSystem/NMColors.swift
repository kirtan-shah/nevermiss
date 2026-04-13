import SwiftUI
import AppKit

// MARK: - NeverMiss Color Palette

extension Color {

    // MARK: Appearance-Adaptive Initializer

    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? dark : light
        }))
    }

    // MARK: Backgrounds
    static let nmBackground = Color(
        light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1),  // #F2F2F7 (systemGroupedBackground)
        dark:  NSColor(srgbRed: 0.102, green: 0.102, blue: 0.118, alpha: 1)   // #1A1A1E
    )
    static let nmSurface = Color(
        light: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),  // #FFFFFF
        dark:  NSColor(srgbRed: 0.141, green: 0.141, blue: 0.157, alpha: 1)   // #242428
    )
    static let nmSurfaceHover = Color(
        light: NSColor(srgbRed: 0.922, green: 0.922, blue: 0.941, alpha: 1),  // #EBEBF0
        dark:  NSColor(srgbRed: 0.180, green: 0.180, blue: 0.204, alpha: 1)   // #2E2E34
    )

    // MARK: Text
    static let nmTextPrimary = Color(
        light: NSColor(srgbRed: 0.102, green: 0.102, blue: 0.118, alpha: 1),  // #1A1A1E
        dark:  NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)   // #F5F5F7
    )
    static let nmTextSecondary = Color(
        light: NSColor(srgbRed: 0.424, green: 0.424, blue: 0.447, alpha: 1),  // #6C6C72
        dark:  NSColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1)   // #8E8E93
    )
    static let nmTextTertiary = Color(
        light: NSColor(srgbRed: 0.710, green: 0.710, blue: 0.729, alpha: 1),  // #B5B5BA (tertiaryLabel)
        dark:  NSColor(srgbRed: 0.388, green: 0.388, blue: 0.400, alpha: 1)   // #636366
    )

    // MARK: Brand
    static let nmAccent = Color(
        light: NSColor(srgbRed: 0.369, green: 0.620, blue: 1.000, alpha: 1),  // #5E9EFF
        dark:  NSColor(srgbRed: 0.369, green: 0.620, blue: 1.000, alpha: 1)   // #5E9EFF (unchanged)
    )

    // MARK: Urgency
    static let nmUrgencyCritical = Color(
        light: NSColor(srgbRed: 1.000, green: 0.231, blue: 0.188, alpha: 1),  // #FF3B30
        dark:  NSColor(srgbRed: 1.000, green: 0.271, blue: 0.227, alpha: 1)   // #FF453A
    )
    static let nmUrgencyHigh = Color(
        light: NSColor(srgbRed: 1.000, green: 0.584, blue: 0.000, alpha: 1),  // #FF9500
        dark:  NSColor(srgbRed: 1.000, green: 0.624, blue: 0.039, alpha: 1)   // #FF9F0A
    )
    static let nmUrgencyMedium = Color(
        light: NSColor(srgbRed: 1.000, green: 0.800, blue: 0.000, alpha: 1),  // #FFCC00
        dark:  NSColor(srgbRed: 1.000, green: 0.839, blue: 0.039, alpha: 1)   // #FFD60A
    )
    static let nmUrgencyLow = Color(
        light: NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1),  // #34C759
        dark:  NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)   // #30D158
    )

    // MARK: Actions
    static let nmSnooze = Color(
        light: NSColor(srgbRed: 0.345, green: 0.337, blue: 0.839, alpha: 1),  // #5856D6 (systemIndigo)
        dark:  NSColor(srgbRed: 0.749, green: 0.545, blue: 0.243, alpha: 1)   // #BF8B3E
    )
    static let nmDismiss = Color(
        light: NSColor(srgbRed: 0.820, green: 0.820, blue: 0.839, alpha: 1),  // #D1D1D6 (systemGray4)
        dark:  NSColor(srgbRed: 0.282, green: 0.282, blue: 0.290, alpha: 1)   // #48484A
    )
    static let nmDismissText = Color(
        light: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1),  // #1C1C1E
        dark:  NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1)   // #FFFFFF
    )

    // MARK: Utility
    static let nmSeparator = Color(
        light: NSColor(srgbRed: 0.898, green: 0.898, blue: 0.918, alpha: 1),  // #E5E5EA
        dark:  NSColor(srgbRed: 0.220, green: 0.220, blue: 0.227, alpha: 1)   // #38383A
    )
    static let nmSuccess = Color(
        light: NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1),  // #34C759
        dark:  NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)   // #30D158
    )

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
