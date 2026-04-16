import SwiftUI

// MARK: - Recommendations ViewModel

@MainActor
final class RecommendationsViewModel: ObservableObject {

    @Published var hotels: [PlaceRecommendation] = []
    @Published var restaurants: [PlaceRecommendation] = []
    @Published var hotelFiltersBroadened: Bool = false
    @Published var restaurantFiltersBroadened: Bool = false
    @Published var isLoadingHotels: Bool = false
    @Published var isLoadingRestaurants: Bool = false
    @Published var hotelError: String?
    @Published var restaurantError: String?
    @Published var selectedHotel: PlaceRecommendation?
    @Published var selectedRestaurants: Set<String> = []
    @Published var hotelSearchResults: [PlaceRecommendation] = []
    @Published var restaurantSearchResults: [PlaceRecommendation] = []
    @Published var isSearchingHotels: Bool = false
    @Published var isSearchingRestaurants: Bool = false

    private var excludedHotelIds: [String] = []
    private var excludedRestaurantIds: [String] = []

    let latitude: Double
    let longitude: Double
    let cityName: String

    var onHotelSelectionChanged: ((PlaceRecommendation?) -> Void)?

    init(
        latitude: Double,
        longitude: Double,
        cityName: String = ""
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.cityName = cityName
    }

    func loadAll() async {
        async let h: () = loadHotels()
        async let r: () = loadRestaurants()
        _ = await (h, r)
    }

    func loadHotels() async {
        isLoadingHotels = true
        hotelError = nil

        var queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
        ]
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

    func loadRestaurants() async {
        isLoadingRestaurants = true
        restaurantError = nil

        var queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
        ]
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

    func refreshHotels() async {
        excludedHotelIds.append(contentsOf: hotels.map(\.placeId))
        await loadHotels()
    }

    func refreshRestaurants() async {
        excludedRestaurantIds.append(contentsOf: restaurants.map(\.placeId))
        await loadRestaurants()
    }

    func selectHotel(_ hotel: PlaceRecommendation) {
        selectedHotel = hotel
        onHotelSelectionChanged?(hotel)
    }

    func toggleRestaurant(_ restaurant: PlaceRecommendation) {
        if selectedRestaurants.contains(restaurant.placeId) {
            selectedRestaurants.remove(restaurant.placeId)
        } else {
            selectedRestaurants.insert(restaurant.placeId)
        }
    }

    func searchHotels(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            hotelSearchResults = []
            return
        }
        isSearchingHotels = true
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "place_type", value: "lodging"),
        ]
        do {
            let response: PlacesResponse = try await APIClient.shared.request(
                .get, path: "/places/search", queryItems: queryItems
            )
            hotelSearchResults = response.results
        } catch {
            hotelSearchResults = []
        }
        isSearchingHotels = false
    }

    func searchRestaurants(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            restaurantSearchResults = []
            return
        }
        isSearchingRestaurants = true
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "place_type", value: "restaurant"),
        ]
        do {
            let response: PlacesResponse = try await APIClient.shared.request(
                .get, path: "/places/search", queryItems: queryItems
            )
            restaurantSearchResults = response.results
        } catch {
            restaurantSearchResults = []
        }
        isSearchingRestaurants = false
    }
}

// MARK: - Place Type

enum PlaceType {
    case hotel
    case restaurant
}

// MARK: - Place Card

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

                    if place.priceRangeMin == nil || place.priceRangeMax == nil {
                        Text("Estimated")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }

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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var placeImage: some View {
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
            .overlay(Image(systemName: "photo").foregroundStyle(DesignTokens.textSecondary))
    }
}
