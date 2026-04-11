import SwiftUI

// MARK: - TimelineBarView

/// Visual timeline showing Morning, Afternoon, and Evening segments for a day.
/// Filled segments have activities; dimmed segments do not.
/// Validates: Requirements 8.1, 8.2, 8.3, 8.4
struct TimelineBarView: View {

    let day: ItineraryDay
    let onSegmentTap: (String) -> Void

    private let segments: [(label: String, color: Color)] = [
        ("Morning", DesignTokens.accentCyan),
        ("Afternoon", DesignTokens.accentBlue),
        ("Evening", .purple),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments, id: \.label) { segment in
                let hasActivities = day.slots.contains { $0.timeSlot.lowercased() == segment.label.lowercased() }
                Button {
                    onSegmentTap(segment.label)
                } label: {
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hasActivities ? segment.color : segment.color.opacity(0.15))
                            .frame(height: 6)
                        Text(segment.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(hasActivities ? segment.color : DesignTokens.textTertiary)
                    }
                }
                .accessibilityLabel("\(segment.label) \(hasActivities ? "has activities" : "empty")")
            }
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingXS)
    }
}
