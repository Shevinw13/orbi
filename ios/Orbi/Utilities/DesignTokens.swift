import SwiftUI

// MARK: - Design Tokens

/// Centralized design tokens for the dark-space UI redesign.
/// All views reference these constants for colors, spacing, radii, animations, and sizes.
enum DesignTokens {

    // MARK: Colors

    static let backgroundPrimary = Color(red: 0.04, green: 0.06, blue: 0.14)
    static let backgroundSecondary = Color(red: 0.08, green: 0.10, blue: 0.20)
    static let surfaceGlass = Color.white.opacity(0.08)
    static let surfaceGlassBorder = Color.white.opacity(0.15)
    static let accentCyan = Color(red: 0.0, green: 0.85, blue: 0.95)
    static let accentBlue = Color(red: 0.2, green: 0.5, blue: 1.0)
    static let accentGradient = LinearGradient(
        colors: [accentCyan, accentBlue],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.35)

    // MARK: Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: Corner Radii

    static let radiusSM: CGFloat = 12
    static let radiusMD: CGFloat = 16
    static let radiusLG: CGFloat = 24
    static let radiusXL: CGFloat = 28

    // MARK: Animation

    static let sheetSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let globeTransition = Animation.easeInOut(duration: 1.2)
    static let pinScale = Animation.spring(response: 0.3, dampingFraction: 0.6)

    // MARK: Sizes

    static let tabBarHeight: CGFloat = 70
    static let searchBarHeight: CGFloat = 44
    static let cityCardFraction: CGFloat = 0.30
    static let preferencesSheetFraction: CGFloat = 0.80
}
