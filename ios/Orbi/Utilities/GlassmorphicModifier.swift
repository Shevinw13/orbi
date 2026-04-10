import SwiftUI

// MARK: - Glassmorphic Modifier

/// A reusable ViewModifier that applies the glassmorphism effect:
/// ultra-thin material blur + translucent surface fill + clipped rounded rect + subtle border stroke.
struct GlassmorphicModifier: ViewModifier {
    var cornerRadius: CGFloat = DesignTokens.radiusLG

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(DesignTokens.surfaceGlass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(DesignTokens.surfaceGlassBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - View Extension

extension View {
    /// Applies glassmorphism styling with the given corner radius.
    /// - Parameter cornerRadius: The corner radius for the rounded rectangle. Defaults to `DesignTokens.radiusLG` (24pt).
    func glassmorphic(cornerRadius: CGFloat = DesignTokens.radiusLG) -> some View {
        modifier(GlassmorphicModifier(cornerRadius: cornerRadius))
    }
}
