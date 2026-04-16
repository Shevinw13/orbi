import SwiftUI

// MARK: - Stays View

/// Displays hotel recommendations with budget tier filtering.
/// Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5
struct StaysView: View {

    @ObservedObject var viewModel: RecommendationsViewModel
    let budgetTier: String
    let numDays: Int
    @ObservedObject var costVM: CostViewModel

    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
                // Section header
                HStack {
                    Label("Hotels", systemImage: "building.2")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    refreshButton
                }
                .padding(.horizontal, DesignTokens.spacingMD)

                if viewModel.hotelFiltersBroadened {
                    filtersBroadenedBanner
                        .padding(.horizontal, DesignTokens.spacingMD)
                }

                if viewModel.isLoadingHotels {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(DesignTokens.accentCyan)
                            .padding(.vertical, 24)
                        Spacer()
                    }
                } else if let error = viewModel.hotelError {
                    VStack(spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.9))
                        Button("Retry") {
                            Task { await viewModel.loadHotels() }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DesignTokens.accentCyan)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DesignTokens.spacingSM)
                    .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                    .padding(.horizontal, DesignTokens.spacingMD)
                } else if viewModel.hotels.isEmpty {
                    Text("No hotels found for this budget tier")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DesignTokens.spacingMD)
                } else {
                    ForEach(viewModel.hotels) { hotel in
                        hotelCard(hotel)
                            .padding(.horizontal, DesignTokens.spacingMD)
                    }
                }

                // Search fallback
                searchSection
                    .padding(.horizontal, DesignTokens.spacingMD)
            }
            .padding(.vertical, DesignTokens.spacingMD)
        }
        .background(DesignTokens.backgroundPrimary)
        .task {
            if viewModel.hotels.isEmpty {
                await viewModel.loadHotels()
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refreshHotels() }
        } label: {
            if viewModel.isLoadingHotels {
                ProgressView().controlSize(.small).tint(DesignTokens.accentCyan)
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(DesignTokens.accentCyan)
            }
        }
        .padding(DesignTokens.spacingSM)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
        .disabled(viewModel.isLoadingHotels)
        .accessibilityLabel("Refresh hotels")
    }

    private var filtersBroadenedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(DesignTokens.accentCyan)
            Text("Filters were broadened to show more results")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(DesignTokens.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
    }

    private func hotelCard(_ hotel: PlaceRecommendation) -> some View {
        let isSelected = viewModel.selectedHotel?.placeId == hotel.placeId
        return Button {
            viewModel.selectHotel(hotel)
            // Trigger cost recalculation
            let rate = estimateNightlyRate(priceLevel: hotel.priceLevel, min: hotel.priceRangeMin, max: hotel.priceRangeMax)
            let isEstimated = hotel.priceRangeMin == nil || hotel.priceRangeMax == nil
            Task {
                await costVM.recalculate(hotelNightlyRate: rate, hotelIsEstimated: isEstimated)
            }
        } label: {
            HStack(spacing: 12) {
                placeImage(hotel)

                VStack(alignment: .leading, spacing: 4) {
                    Text(hotel.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if hotel.rating > 0 {
                            Label(String(format: "%.1f", hotel.rating), systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        Text(PriceFormatter.hotelPrice(min: hotel.priceRangeMin, max: hotel.priceRangeMax, tier: hotel.priceLevel))
                            .foregroundStyle(DesignTokens.accentCyan)
                    }
                    .font(.caption)

                    if hotel.priceRangeMin == nil || hotel.priceRangeMax == nil {
                        Text("Estimated")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }

                    if let count = hotel.reviewCount {
                        Text("Based on \(count) reviews")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }

                    ExternalLinkButton(placeName: hotel.name, city: viewModel.cityName)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.accentCyan)
                        .font(.title3)
                }
            }
            .padding(DesignTokens.spacingSM)
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusMD)
                    .stroke(isSelected ? DesignTokens.accentCyan : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hotel.name), rating \(String(format: "%.1f", hotel.rating))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func placeImage(_ place: PlaceRecommendation) -> some View {
        if let urlString = place.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    imagePlaceholder
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
            .fill(DesignTokens.surfaceGlass)
            .frame(width: 64, height: 64)
            .overlay(
                Image(systemName: "building.2")
                    .foregroundStyle(DesignTokens.textSecondary)
            )
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Text("Search Hotels")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.textTertiary)
                TextField("Search by name or type...", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .onSubmit {
                        Task { await viewModel.searchHotels(query: searchQuery) }
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        viewModel.hotelSearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.textTertiary)
                    }
                }
                if viewModel.isSearchingHotels {
                    ProgressView().controlSize(.small).tint(DesignTokens.accentCyan)
                }
            }
            .padding(DesignTokens.spacingSM)
            .glassmorphic(cornerRadius: DesignTokens.radiusSM)
            .onChange(of: searchQuery) { _, newValue in
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard searchQuery == newValue else { return }
                    await viewModel.searchHotels(query: newValue)
                }
            }

            if !viewModel.hotelSearchResults.isEmpty {
                Text("Results for \"\(searchQuery)\"")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accentCyan)

                ForEach(viewModel.hotelSearchResults) { hotel in
                    hotelCard(hotel)
                }
            } else if !searchQuery.isEmpty && !viewModel.isSearchingHotels {
                Text("No results found")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
    }

    private func estimateNightlyRate(priceLevel: String, min: Double?, max: Double?) -> Double {
        if let min = min, let max = max, min > 0, max > 0 {
            return (min + max) / 2.0
        }
        switch priceLevel {
        case "$": return 60
        case "$$": return 120
        case "$$$": return 200
        case "$$$$": return 350
        case "$$$$$": return 500
        default: return 150
        }
    }
}
