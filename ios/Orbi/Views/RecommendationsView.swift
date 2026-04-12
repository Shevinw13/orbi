import SwiftUI

// MARK: - Recommendations ViewModel

/// Manages hotel and restaurant recommendation state, refresh, and exclusion tracking.
/// Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5
@MainActor
final class RecommendationsViewModel: ObservableObject {

    // Data
    @Published var hotels: [PlaceRecommendation] = []
    @Published var restaurants: [PlaceRecommendation] = []
    @Published var hotelFiltersBroadened: Bool = false
    @Published var restaurantFiltersBroadened: Bool = false

    // Loading state
    @Published var isLoadingHotels: Bool = false
    @Published var isLoadingRestaurants: Bool = false
    @Published var hotelError: String?
    @Published var restaurantError: String?

    // Selection
    @Published var selectedHotel: PlaceRecommendation?
    @Published var selectedRestaurants: Set<String> = []

    // Exclusion tracking for refresh (Req 7.4)
    private var excludedHotelIds: [String] = []
    private var excludedRestaurantIds: [String] = []

    // Query parameters
    let latitude: Double
    let longitude: Double
    let hotelPriceRange: String?
    let hotelVibe: String?
    let restaurantPriceRange: String?
    let cuisineType: String?
    let cityName: String

    /// Callback when hotel selection changes (triggers cost recalculation).
    var onHotelSelectionChanged: ((PlaceRecommendation?) -> Void)?

    init(
        latitude: Double,
        longitude: Double,
        hotelPriceRange: String? = nil,
        hotelVibe: String? = nil,
        restaurantPriceRange: String? = nil,
        cuisineType: String? = nil,
        cityName: String = ""
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.hotelPriceRange = hotelPriceRange
        self.hotelVibe = hotelVibe
        self.restaurantPriceRange = restaurantPriceRange
        self.cuisineType = cuisineType
        self.cityName = cityName
    }

    // MARK: - Load Initial Data

    func loadAll() async {
        async let h: () = loadHotels()
        async let r: () = loadRestaurants()
        _ = await (h, r)
    }

    // MARK: - Hotels (Req 7.1)

    func loadHotels() async {
        isLoadingHotels = true
        hotelError = nil

        var queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
        ]
        if let hotelPriceRange { queryItems.append(URLQueryItem(name: "price_range", value: hotelPriceRange)) }
        if let hotelVibe { queryItems.append(URLQueryItem(name: "vibe", value: hotelVibe)) }
        for id in excludedHotelIds {
            queryItems.append(URLQueryItem(name: "excluded_ids", value: id))
        }

        do {
            let response: PlacesResponse = try await APIClient.shared.request(
                .get, path: "/places/hotels", queryItems: queryItems
            )
            hotels = response.results
            hotelFiltersBroadened = response.filtersBroadened
            if selectedHotel == nil, let first = hotels.first {
                selectHotel(first)
            }
        } catch let error as APIError {
            hotelError = error.errorDescription
        } catch {
            hotelError = "Failed to load hotels. Please try again."
        }

        isLoadingHotels = false
    }

    // MARK: - Restaurants (Req 7.2)

    func loadRestaurants() async {
        isLoadingRestaurants = true
        restaurantError = nil

        var queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
        ]
        if let restaurantPriceRange { queryItems.append(URLQueryItem(name: "price_range", value: restaurantPriceRange)) }
        if let cuisineType { queryItems.append(URLQueryItem(name: "cuisine", value: cuisineType)) }
        for id in excludedRestaurantIds {
            queryItems.append(URLQueryItem(name: "excluded_ids", value: id))
        }

        do {
            let response: PlacesResponse = try await APIClient.shared.request(
                .get, path: "/places/restaurants", queryItems: queryItems
            )
            restaurants = response.results
            restaurantFiltersBroadened = response.filtersBroadened
        } catch let error as APIError {
            restaurantError = error.errorDescription
        } catch {
            restaurantError = "Failed to load restaurants. Please try again."
        }

        isLoadingRestaurants = false
    }

    // MARK: - Refresh (Req 7.4)

    func refreshHotels() async {
        excludedHotelIds.append(contentsOf: hotels.map(\.placeId))
        await loadHotels()
    }

    func refreshRestaurants() async {
        excludedRestaurantIds.append(contentsOf: restaurants.map(\.placeId))
        await loadRestaurants()
    }

    // MARK: - Selection

    func selectHotel(_ hotel: PlaceRecommendation) {
        selectedHotel = hotel
        onHotelSelectionChanged?(hotel)
    }

    // MARK: - Restaurant Selection (Req 11.1, 11.2, 11.3, 11.4)

    func toggleRestaurant(_ restaurant: PlaceRecommendation) {
        if selectedRestaurants.contains(restaurant.placeId) {
            selectedRestaurants.remove(restaurant.placeId)
        } else {
            selectedRestaurants.insert(restaurant.placeId)
        }
    }
}



// MARK: - Recommendations View

/// Displays top 3 hotel and restaurant recommendations with refresh and filter-broadened indication.
/// Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5, 10.1, 10.2, 10.3, 10.4
struct RecommendationsView: View {

    @ObservedObject var viewModel: RecommendationsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
                hotelsSection
                restaurantsSection
            }
            .padding(DesignTokens.spacingMD)
        }
        .background(DesignTokens.backgroundPrimary)
        .task {
            if viewModel.hotels.isEmpty && viewModel.restaurants.isEmpty {
                await viewModel.loadAll()
            }
        }
    }

    // MARK: - Hotels Section (Req 7.1, 7.3)

    private var hotelsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            HStack {
                Label("Hotels", systemImage: "building.2")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                refreshButton(isLoading: viewModel.isLoadingHotels) {
                    Task { await viewModel.refreshHotels() }
                }
                .accessibilityLabel("Refresh hotels")
            }

            if viewModel.hotelFiltersBroadened {
                filtersBroadenedBanner
            }

            if viewModel.isLoadingHotels {
                loadingPlaceholder
            } else if let error = viewModel.hotelError {
                errorBanner(message: error) {
                    Task { await viewModel.loadHotels() }
                }
            } else if viewModel.hotels.isEmpty {
                emptyPlaceholder(text: "No hotels found")
            } else {
                ForEach(viewModel.hotels) { hotel in
                    PlaceCard(
                        place: hotel,
                        placeType: .hotel,
                        isSelected: viewModel.selectedHotel?.placeId == hotel.placeId,
                        city: viewModel.cityName,
                        onTap: { viewModel.selectHotel(hotel) }
                    )
                }
            }
        }
    }

    // MARK: - Restaurants Section (Req 7.2, 7.3)

    private var restaurantsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            HStack {
                Label("Restaurants", systemImage: "fork.knife")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                refreshButton(isLoading: viewModel.isLoadingRestaurants) {
                    Task { await viewModel.refreshRestaurants() }
                }
                .accessibilityLabel("Refresh restaurants")
            }

            if viewModel.restaurantFiltersBroadened {
                filtersBroadenedBanner
            }

            if viewModel.isLoadingRestaurants {
                loadingPlaceholder
            } else if let error = viewModel.restaurantError {
                errorBanner(message: error) {
                    Task { await viewModel.loadRestaurants() }
                }
            } else if viewModel.restaurants.isEmpty {
                emptyPlaceholder(text: "No restaurants found")
            } else {
                ForEach(viewModel.restaurants) { restaurant in
                    PlaceCard(
                        place: restaurant,
                        placeType: .restaurant,
                        isSelected: viewModel.selectedRestaurants.contains(restaurant.placeId),
                        city: viewModel.cityName,
                        onTap: { viewModel.toggleRestaurant(restaurant) }
                    )
                }
            }
        }
    }

    // MARK: - Shared Components

    private func refreshButton(isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(DesignTokens.accentCyan)
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(DesignTokens.accentCyan)
            }
        }
        .padding(DesignTokens.spacingSM)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
        .disabled(isLoading)
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
        .accessibilityLabel("Filters were broadened to show more results")
    }

    private var loadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(DesignTokens.accentCyan)
                .padding(.vertical, 24)
            Spacer()
        }
    }

    private func emptyPlaceholder(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DesignTokens.spacingMD)
    }

    private func errorBanner(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red.opacity(0.9))
            Button("Retry", action: retry)
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.accentCyan)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.spacingSM)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
    }
}


// MARK: - Place Type

/// Distinguishes hotel vs restaurant for pricing format selection.
enum PlaceType {
    case hotel
    case restaurant
}

// MARK: - Place Card (Req 7.3)

/// Displays a single place recommendation with name, rating, price level, and image.
struct PlaceCard: View {

    let place: PlaceRecommendation
    let placeType: PlaceType
    let isSelected: Bool
    let city: String
    let onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                placeImage

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if place.rating > 0 {
                            if let source = place.ratingSource {
                                Label("\(String(format: "%.1f", place.rating)) (\(source))", systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                            } else {
                                Label(String(format: "%.1f", place.rating), systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(placeType == .hotel
                             ? PriceFormatter.hotelPrice(min: place.priceRangeMin, max: place.priceRangeMax, tier: place.priceLevel)
                             : PriceFormatter.restaurantPrice(min: place.priceRangeMin, max: place.priceRangeMax, tier: place.priceLevel))
                            .foregroundStyle(DesignTokens.accentCyan)
                    }
                    .font(.caption)

                    Text("Estimated")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)

                    // Review count (Req 8.2)
                    if let count = place.reviewCount {
                        Text("Based on \(count) reviews")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }

                    ExternalLinkButton(placeName: place.name, city: city)
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
        .accessibilityLabel("\(place.name), rating \(String(format: "%.1f", place.rating)), \(placeType == .hotel ? PriceFormatter.hotelPrice(min: place.priceRangeMin, max: place.priceRangeMax, tier: place.priceLevel) : PriceFormatter.restaurantPrice(min: place.priceRangeMin, max: place.priceRangeMax, tier: place.priceLevel))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var placeImage: some View {
        if let urlString = place.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                Image(systemName: "photo")
                    .foregroundStyle(DesignTokens.textSecondary)
            )
    }
}

// MARK: - Preview

#Preview {
    let vm = RecommendationsViewModel(
        latitude: 35.6762,
        longitude: 139.6503,
        hotelPriceRange: "$$",
        restaurantPriceRange: "$$",
        cityName: "Tokyo"
    )
    vm.hotels = [
        PlaceRecommendation(placeId: "h1", name: "Park Hyatt Tokyo", rating: 4.6, priceLevel: "$$", imageUrl: nil, latitude: 35.6867, longitude: 139.6906),
        PlaceRecommendation(placeId: "h2", name: "The Peninsula Tokyo", rating: 4.7, priceLevel: "$$", imageUrl: nil, latitude: 35.6750, longitude: 139.7630),
        PlaceRecommendation(placeId: "h3", name: "Aman Tokyo", rating: 4.8, priceLevel: "$$", imageUrl: nil, latitude: 35.6860, longitude: 139.7640),
    ]
    vm.restaurants = [
        PlaceRecommendation(placeId: "r1", name: "Sushi Dai", rating: 4.7, priceLevel: "$", imageUrl: nil, latitude: 35.6655, longitude: 139.7710),
        PlaceRecommendation(placeId: "r2", name: "Ichiran Ramen", rating: 4.5, priceLevel: "$", imageUrl: nil, latitude: 35.6600, longitude: 139.7000),
        PlaceRecommendation(placeId: "r3", name: "Gonpachi Nishi-Azabu", rating: 4.3, priceLevel: "$", imageUrl: nil, latitude: 35.6560, longitude: 139.7260),
    ]
    vm.selectedHotel = vm.hotels.first
    return NavigationStack {
        RecommendationsView(viewModel: vm)
            .navigationTitle("Recommendations")
    }
}
