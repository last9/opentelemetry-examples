import SwiftUI

// MARK: - Design tokens
//
// Visual language mirrors the Last9 RUM React Native reference app: a soft grey
// canvas, white cards with a hairline border and light shadow, and a single
// purple accent. Kept in one place so every screen stays consistent.

enum Theme {
    /// Accent purple (#6C63FF).
    static let accent = Color(red: 0.42, green: 0.39, blue: 1.0)
    /// Light-purple tint used for the feature badge (#F0EFFF).
    static let accentTint = Color(red: 0.94, green: 0.937, blue: 1.0)
    /// Screen background (#F8F9FA).
    static let background = Color(red: 0.973, green: 0.976, blue: 0.98)
    /// Card border (#EEEEEE).
    static let cardBorder = Color(red: 0.933, green: 0.933, blue: 0.933)

    // Status colors.
    static let ok = Color(red: 0.0, green: 0.722, blue: 0.580)        // #00B894
    static let error = Color(red: 1.0, green: 0.420, blue: 0.420)     // #FF6B6B
    static let warning = Color(red: 1.0, green: 0.624, blue: 0.263)   // #FF9F43
    static let violet = Color(red: 0.424, green: 0.361, blue: 0.906)  // #6C5CE7
    static let lilac = Color(red: 0.635, green: 0.608, blue: 0.996)   // #A29BFE
    static let neutral = Color(red: 0.388, green: 0.431, blue: 0.459) // #636E72

    static let textPrimary = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let textSecondary = Color(red: 0.533, green: 0.533, blue: 0.533)
}

// MARK: - Card style

/// White rounded card with a hairline border and a soft shadow — the base
/// container used throughout the app.
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}

// MARK: - Section header + hint

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct Hint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Feature badge

/// Light-purple card listing the RUM features a screen demonstrates.
struct FeatureBadge: View {
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RUM FEATURES ON THIS SCREEN")
                .font(.system(size: 11, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(Theme.accent)
            ForEach(features, id: \.self) { feature in
                Text("✓ \(feature)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentTint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Buttons

/// Purple filled primary button.
struct PrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accent.opacity(disabled ? 0.5 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// White outline pill button (e.g. Sign Out).
struct OutlineButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .overlay(
                    Capsule().stroke(Theme.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// White card with an emoji/symbol on top of a small label — for grid actions.
struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(icon).font(.system(size: 22))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - API result card

/// Result of a network request rendered as a white card with a colored leading
/// bar: green when ok, red on error.
struct ApiResultCard: View {
    let label: String
    let status: Int
    let durationMs: Int
    var ok: Bool
    var detail: String? = nil

    private var barColor: Color {
        ok ? Theme.ok : (status == 0 ? Theme.neutral : Theme.error)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(barColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(status == 0 ? "ERR" : String(status)) · \(durationMs)ms")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(barColor)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(12)
        }
        .cardStyle(cornerRadius: 8)
    }
}

// MARK: - Error button

/// White card with a colored leading bar; bold title plus a small subtitle.
struct ErrorButton: View {
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avatar

/// Round purple avatar with initials, used on the Profile card.
struct Avatar: View {
    let initials: String

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent).frame(width: 64, height: 64)
            Text(initials)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Screen container

/// Wraps screen content in the grey canvas + scroll view with consistent padding.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(16)
            }
        }
    }
}
