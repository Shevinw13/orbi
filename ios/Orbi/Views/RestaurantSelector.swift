import SwiftUI

/// Horizontal scroll of compact restaurant cards for pre-selection in trip setup.
/// Validates: Requirements 1.1, 1.2, 1.3, 1.5, 10.5
struct RestaurantSelector: View {
    @ObservedObject var viewModel: RecommendationsViewModel
    @Binding var selectedIds: Set<String>
    let maxSelections: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Text("Pre-select Restaurants (optional)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)

            if viewModel.isLoadingRestaurants {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(DesignTokens.accentCyan)
                    Spacer()
                }
                .padding(.vertical, DesignTokens.spacingSM)
            } else if viewModel.restaurants.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.spacingSM) {
                        ForEach(viewModel.restaurants) { restaurant in
                            compactCard(restaurant: restaurant)
                        }
                    }
                }

                if selectedIds.count > 0 {
                    Text("\(selectedIds.count)/\(maxSelections) selected")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }
        }
    }

    private func compactCard(restaurant: PlaceRecommendation) -> some View {
        let isSelected = selectedIds.contains(restaurant.placeId)
        return Button {
            toggle(restaurant)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(restaurant.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(restaurant.priceLevel)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(PriceFormatter.restaurantPrice(min: restaurant.priceRangeMin, max: restaurant.priceRangeMax, tier: restaurant.priceLevel))
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.accentCyan)
            }
            .padding(DesignTokens.spacingSM)
            .frame(width: 140)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                    .fill(DesignTokens.surfaceGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                    .stroke(isSelected ? DesignTokens.accentCyan : DesignTokens.surfaceGlassBorder, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(restaurant.name), \(isSelected ? "selected" : "not selected")")
    }

    private func toggle(_ restaurant: PlaceRecommendation) {
        if selectedIds.contains(restaurant.placeId) {
            selectedIds.remove(restaurant.placeId)
        } else if selectedIds.count < maxSelections {
            selectedIds.insert(restaurant.placeId)
        }
    }
}
