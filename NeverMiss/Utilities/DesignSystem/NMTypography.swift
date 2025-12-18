import SwiftUI

// MARK: - NeverMiss Typography Scale

extension Font {

    // MARK: - Properties

    /// Alert meeting title — 36pt bold
    static let nmDisplayLarge: Font = .system(size: 36, weight: .bold)

    /// Onboarding headings, launch title — 28pt bold
    static let nmDisplayMedium: Font = .system(size: 28, weight: .bold)

    /// Section titles, popover header — 16pt semibold
    static let nmHeadline: Font = .system(size: 16, weight: .semibold)

    /// Standard body text — 14pt regular
    static let nmBody: Font = .system(size: 14, weight: .regular)

    /// Emphasized body (event titles) — 14pt medium
    static let nmBodyMedium: Font = .system(size: 14, weight: .medium)

    /// Metadata, secondary info — 12pt regular
    static let nmCaption: Font = .system(size: 12, weight: .regular)

    /// Badge labels, section headers — 12pt medium
    static let nmCaptionMedium: Font = .system(size: 12, weight: .medium)

    /// Times, digits — 14pt medium monospaced
    static let nmMono: Font = .system(size: 14, weight: .medium, design: .monospaced)

    /// Alert countdown digits — 48pt bold monospaced
    static let nmMonoLarge: Font = .system(size: 48, weight: .bold, design: .monospaced)

    /// Countdown in menu bar header — 20pt bold monospaced
    static let nmMonoMedium: Font = .system(size: 20, weight: .bold, design: .monospaced)

    /// Pill badges — 12pt semibold rounded
    static let nmRounded: Font = .system(size: 12, weight: .semibold, design: .rounded)
}
