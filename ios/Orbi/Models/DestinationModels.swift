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
