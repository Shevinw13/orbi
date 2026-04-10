import SwiftUI

/// The Orbi app logo — a gradient globe (blue→green) with a white orbital ring.
/// Matches the brand logo: sphere with cyan-blue-green gradient, white tilted orbit ring.
struct OrbiLogo: View {
    var size: CGFloat = 200
    var showText: Bool = true

    var body: some View {
        VStack(spacing: size * 0.08) {
            ZStack {
                // Globe sphere — blue to green gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.4, blue: 0.85),   // blue
                                Color(red: 0.0, green: 0.65, blue: 0.75),  // teal
                                Color(red: 0.2, green: 0.75, blue: 0.3),   // green
                                Color(red: 0.5, green: 0.85, blue: 0.2),   // lime highlight
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)

                // Specular highlight on globe
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.0),
                            ],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.25
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)

                // Orbital ring — white, tilted ellipse going behind and in front of globe
                // Back part of ring (behind globe)
                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.15),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: size * 0.025
                    )
                    .frame(width: size * 0.95, height: size * 0.3)
                    .rotationEffect(.degrees(-30))

                // Globe sphere again on top (to create the "ring goes behind" effect)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.4, blue: 0.85),
                                Color(red: 0.0, green: 0.65, blue: 0.75),
                                Color(red: 0.2, green: 0.75, blue: 0.3),
                                Color(red: 0.5, green: 0.85, blue: 0.2),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.62, height: size * 0.62)

                // Specular highlight again
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.0),
                            ],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.22
                        )
                    )
                    .frame(width: size * 0.62, height: size * 0.62)

                // Front part of ring (in front of globe) — only the top-right arc
                Ellipse()
                    .trim(from: 0.55, to: 0.95)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                Color.white.opacity(0.5),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round)
                    )
                    .frame(width: size * 0.95, height: size * 0.3)
                    .rotationEffect(.degrees(-30))
            }
            .frame(width: size, height: size * 0.8)

            if showText {
                Text("Orbi")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.1, green: 0.15, blue: 0.3))
            }
        }
    }
}

/// Dark-mode version of the logo for use on dark backgrounds (login screen, etc.)
struct OrbiLogoDark: View {
    var size: CGFloat = 200
    var showText: Bool = true

    var body: some View {
        VStack(spacing: size * 0.08) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.4, blue: 0.85),
                                Color(red: 0.0, green: 0.65, blue: 0.75),
                                Color(red: 0.2, green: 0.75, blue: 0.3),
                                Color(red: 0.5, green: 0.85, blue: 0.2),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.0)],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: size * 0.25
                        )
                    )
                    .frame(width: size * 0.7, height: size * 0.7)

                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.15)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        lineWidth: size * 0.025
                    )
                    .frame(width: size * 0.95, height: size * 0.3)
                    .rotationEffect(.degrees(-30))

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.1, green: 0.4, blue: 0.85),
                                Color(red: 0.0, green: 0.65, blue: 0.75),
                                Color(red: 0.2, green: 0.75, blue: 0.3),
                                Color(red: 0.5, green: 0.85, blue: 0.2),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.62, height: size * 0.62)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.0)],
                            center: UnitPoint(x: 0.35, y: 0.25),
                            startRadius: 0, endRadius: size * 0.22
                        )
                    )
                    .frame(width: size * 0.62, height: size * 0.62)

                Ellipse()
                    .trim(from: 0.55, to: 0.95)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.5)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round)
                    )
                    .frame(width: size * 0.95, height: size * 0.3)
                    .rotationEffect(.degrees(-30))
            }
            .frame(width: size, height: size * 0.8)

            if showText {
                Text("Orbi")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview("Light") {
    OrbiLogo(size: 200)
}

#Preview("Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        OrbiLogoDark(size: 200)
    }
}
