import SwiftUI

// MARK: - Itinerary Card View

/// Compact card for the Explore feed showing shared itinerary summary.
/// Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5
struct ItineraryCardView: View {

    let card: SharedItineraryCard

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            // Cover photo or gradient placeholder
            coverImage
                .frame(width: 200, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(2)

                Text(card.destination)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(card.numDays) days", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textSecondary)

                    Text(budgetIndicator)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 8) {
                    if let username = card.creatorUsername {
                        Label(username, systemImage: "person.circle")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.accentCyan)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                        Text("\(card.saveCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .padding(.horizontal, DesignTokens.spacingSM)
            .padding(.bottom, DesignTokens.spacingSM)
        }
        .frame(width: 200)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title), \(card.destination), \(card.numDays) days")
    }

    private var budgetIndicator: String {
        String(repeating: "$", count: max(1, min(5, card.budgetLevel)))
    }

    @ViewBuilder
    private var coverImage: some View {
        if let urlString = card.coverPhotoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    gradientPlaceholder
                default:
                    ProgressView().tint(DesignTokens.accentCyan).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            gradientPlaceholder
        }
    }

    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [DesignTokens.accentCyan.opacity(0.3), DesignTokens.accentBlue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
