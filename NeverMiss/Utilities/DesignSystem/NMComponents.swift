import SwiftUI

// MARK: - NMCard

struct NMCard<Content: View>: View {

    // MARK: - Properties

    var cornerRadius: CGFloat = NMSpacing.radiusMd
    var showBorder: Bool = true
    @ViewBuilder let content: Content

    // MARK: - Body

    var body: some View {
        content
            .background(Color.nmSurface)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(showBorder ? 0.03 : 0), lineWidth: 1)
            )
    }
}

// MARK: - NMBadge

struct NMBadge: View {

    // MARK: - Properties

    let icon: String
    let text: String
    var color: Color = .nmAccent

    // MARK: - Body

    var body: some View {
        HStack(spacing: NMSpacing.sm) {
            Image(systemName: icon)
                .font(.nmCaptionMedium)
            Text(text)
                .font(.nmCaptionMedium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, NMSpacing.md)
        .padding(.vertical, NMSpacing.xs + 1)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - NMProgressRing

struct NMProgressRing: View {

    // MARK: - Properties

    let progress: Double
    var color: Color = .nmUrgencyHigh
    var size: CGFloat = 120
    var lineWidth: CGFloat = 4

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            // Foreground ring
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.3), radius: 8)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - NMKeyboardHint

struct NMKeyboardHint: View {

    // MARK: - Properties

    let key: String
    let action: String

    // MARK: - Body

    var body: some View {
        HStack(spacing: NMSpacing.sm) {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, NMSpacing.sm + 2)
                .padding(.vertical, NMSpacing.xs + 2)
                .background(Color.white.opacity(0.1))
                .clipShape(.rect(cornerRadius: NMSpacing.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: NMSpacing.radiusSm)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            Text(action)
                .font(.nmBody)
        }
        .foregroundStyle(Color.nmTextSecondary)
    }
}
