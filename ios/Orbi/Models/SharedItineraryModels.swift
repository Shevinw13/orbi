import Foundation

// MARK: - Shared Itinerary Card

/// Card-level data for the Explore feed.
/// Validates: Requirements 3.1, 5.1, 8.1
struct SharedItineraryCard: Codable, Identifiable {
    let id: String
    let title: String
    let destination: String
    let numDays: Int
    let budgetLevel: Int
    let coverPhotoUrl: String?
    let creatorUsername: String?
    let saveCount: Int
    let tags: [String]?
}

// MARK: - Shared Itinerary Detail

/// Full detail including itinerary JSONB.
/// Validates: Requirements 5.1, 8.2
struct SharedItineraryDetail: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let destination: String
    let destinationLatLng: String?
    let numDays: Int
    let budgetLevel: Int
    let coverPhotoUrl: String?
    let creatorUsername: String?
    let saveCount: Int
    let tags: [String]?
    let itinerary: [String: AnyCodableValue]?
    let createdAt: String
}

// MARK: - Explore Section

/// A section in the Explore feed (Featured, Trending, etc.).
struct ExploreSection: Codable, Identifiable {
    let id: String
    let title: String
    let sectionType: String
    let items: [SharedItineraryCard]
}

// MARK: - Explore Feed Response

/// Paginated list response from the backend.
struct ExploreFeedResponse: Codable {
    let items: [SharedItineraryCard]
    let total: Int
}

// MARK: - Publish Request

/// Request body for publishing a trip to the Explore library.
struct SharedItineraryPublishRequest: Encodable {
    let sourceTripId: String
    let coverPhotoUrl: String
    let title: String
    let description: String
    let destination: String
    let budgetLevel: Int
    let tags: [String]
}

// MARK: - Copy Response

/// Response after copying a shared itinerary to My Trips.
struct CopyResponse: Codable {
    let tripId: String
}
