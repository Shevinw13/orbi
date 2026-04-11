import Foundation

// MARK: - Destination Suggestion

/// A single destination suggestion returned by `GET /search/destinations`.
/// Requirements: 2.2
struct DestinationSuggestion: Identifiable, Decodable, Equatable {
    let name: String
    let placeId: String
    let latitude: Double
    let longitude: Double

    var id: String { placeId }
}

// MARK: - Search Response

/// Wrapper for the `/search/destinations` JSON response.
/// Requirements: 2.2
struct DestinationSearchResponse: Decodable {
    let results: [DestinationSuggestion]
}

// MARK: - Explore Category (Req 4.1, 4.2, 4.4)

enum ExploreCategory: String, CaseIterable, Identifiable {
    case foodie = "Foodie"
    case adventure = "Adventure"
    case relaxation = "Relaxation"
    case nightlife = "Nightlife"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .foodie: return "fork.knife"
        case .adventure: return "figure.hiking"
        case .relaxation: return "leaf.fill"
        case .nightlife: return "moon.stars.fill"
        }
    }
}

// MARK: - Explore Overlay Models (Req 2.1, 2.2, 2.3)

struct ExploreOverlay: Codable, Identifiable {
    let category: String
    let title: String
    let destinations: [OverlayDestination]

    var id: String { category }
}

struct OverlayDestination: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
}

struct ExploreOverlaysResponse: Codable {
    let overlays: [ExploreOverlay]
}

// MARK: - Weather Models (Req 17.1, 17.2, 17.3)

struct DestinationWeather: Codable {
    let tempHigh: Double
    let tempLow: Double
    let condition: String
    let bestTimeToVisit: String
}
