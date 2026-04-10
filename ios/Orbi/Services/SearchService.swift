import Foundation

// MARK: - Search Service

/// Calls `GET /search/destinations?q=` via APIClient to fetch autocomplete suggestions.
/// Falls back to local city data when the backend is unreachable.
/// Requirements: 2.2
actor SearchService {

    static let shared = SearchService()

    private let client = APIClient.shared

    /// Local city database for offline search.
    private let localCities: [DestinationSuggestion] = [
        DestinationSuggestion(name: "Tokyo, Japan", placeId: "tokyo", latitude: 35.6762, longitude: 139.6503),
        DestinationSuggestion(name: "Paris, France", placeId: "paris", latitude: 48.8566, longitude: 2.3522),
        DestinationSuggestion(name: "New York, USA", placeId: "newyork", latitude: 40.7128, longitude: -74.0060),
        DestinationSuggestion(name: "London, UK", placeId: "london", latitude: 51.5074, longitude: -0.1278),
        DestinationSuggestion(name: "Sydney, Australia", placeId: "sydney", latitude: -33.8688, longitude: 151.2093),
        DestinationSuggestion(name: "Dubai, UAE", placeId: "dubai", latitude: 25.2048, longitude: 55.2708),
        DestinationSuggestion(name: "Rome, Italy", placeId: "rome", latitude: 41.9028, longitude: 12.4964),
        DestinationSuggestion(name: "Barcelona, Spain", placeId: "barcelona", latitude: 41.3874, longitude: 2.1686),
        DestinationSuggestion(name: "Bangkok, Thailand", placeId: "bangkok", latitude: 13.7563, longitude: 100.5018),
        DestinationSuggestion(name: "Istanbul, Turkey", placeId: "istanbul", latitude: 41.0082, longitude: 28.9784),
        DestinationSuggestion(name: "Bali, Indonesia", placeId: "bali", latitude: -8.3405, longitude: 115.0920),
        DestinationSuggestion(name: "Cape Town, South Africa", placeId: "capetown", latitude: -33.9249, longitude: 18.4241),
        DestinationSuggestion(name: "Rio de Janeiro, Brazil", placeId: "rio", latitude: -22.9068, longitude: -43.1729),
        DestinationSuggestion(name: "Lisbon, Portugal", placeId: "lisbon", latitude: 38.7223, longitude: -9.1393),
        DestinationSuggestion(name: "Seoul, South Korea", placeId: "seoul", latitude: 37.5665, longitude: 126.9780),
        DestinationSuggestion(name: "Mexico City, Mexico", placeId: "mexicocity", latitude: 19.4326, longitude: -99.1332),
        DestinationSuggestion(name: "Amsterdam, Netherlands", placeId: "amsterdam", latitude: 52.3676, longitude: 4.9041),
        DestinationSuggestion(name: "Prague, Czech Republic", placeId: "prague", latitude: 50.0755, longitude: 14.4378),
        DestinationSuggestion(name: "Marrakech, Morocco", placeId: "marrakech", latitude: 31.6295, longitude: -7.9811),
        DestinationSuggestion(name: "Singapore", placeId: "singapore", latitude: 1.3521, longitude: 103.8198),
    ]

    /// Fetch destination suggestions for the given query.
    func searchDestinations(query: String) async throws -> [DestinationSuggestion] {
        // Try backend first, fall back to local search
        do {
            let response: DestinationSearchResponse = try await client.request(
                .get,
                path: "/search/destinations",
                queryItems: [URLQueryItem(name: "q", value: query)],
                requiresAuth: true
            )
            return response.results
        } catch {
            // Offline fallback: filter local cities
            let lowered = query.lowercased()
            return localCities.filter { $0.name.lowercased().contains(lowered) }
        }
    }
}
