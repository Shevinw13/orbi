import Foundation

// MARK: - Trip Preferences Request

/// Preferences payload sent to `POST /trips/generate`.
/// Validates: Requirements 3.1, 3.4, 3.5
struct TripPreferencesRequest: Encodable {
    let destination: String
    let latitude: Double
    let longitude: Double
    let numDays: Int
    let hotelPriceRange: String
    let hotelVibe: String?
    let restaurantPriceRange: String
    let cuisineType: String?
    let vibe: String
}

// MARK: - Itinerary Response

/// Top-level itinerary returned from `POST /trips/generate`.
struct ItineraryResponse: Codable {
    let destination: String
    let numDays: Int
    let vibe: String
    var days: [ItineraryDay]
}

struct ItineraryDay: Codable, Identifiable {
    let dayNumber: Int
    var slots: [ItinerarySlot]
    let restaurant: ItineraryRestaurant?

    var id: Int { dayNumber }
}

struct ItinerarySlot: Codable, Identifiable, Equatable {
    var timeSlot: String
    var activityName: String
    var description: String
    var latitude: Double
    var longitude: Double
    var estimatedDurationMin: Int
    var travelTimeToNextMin: Int?
    var estimatedCostUsd: Double?

    var id: String { "\(timeSlot)-\(activityName)" }

    static func == (lhs: ItinerarySlot, rhs: ItinerarySlot) -> Bool {
        lhs.timeSlot == rhs.timeSlot && lhs.activityName == rhs.activityName
    }
}

struct ItineraryRestaurant: Codable {
    let name: String
    let cuisine: String
    let priceLevel: String
    let rating: Double
    let latitude: Double
    let longitude: Double
    let imageUrl: String?
}

// MARK: - Replace Activity

/// Request body for `POST /trips/replace-item`.
/// Validates: Requirement 5.5
struct ReplaceActivityRequest: Encodable {
    let destination: String
    let dayNumber: Int
    let timeSlot: String
    let currentActivityName: String
    let existingActivities: [String]
    let vibe: String
}

// MARK: - Cost Breakdown

/// Cost breakdown returned by the Cost_Estimator.
/// Validates: Requirements 8.1, 8.2, 8.3, 8.4
struct CostBreakdown: Codable {
    let hotelTotal: Double
    let foodTotal: Double
    let activitiesTotal: Double
    let total: Double
    let perDay: [DayCost]
}

struct DayCost: Codable, Identifiable {
    let day: Int
    let hotel: Double
    let food: Double
    let activities: Double
    let subtotal: Double

    var id: Int { day }
}

// MARK: - Place Recommendation

/// A single place recommendation returned by the Place_Service.
/// Validates: Requirement 7.3
struct PlaceRecommendation: Codable, Identifiable, Equatable {
    let placeId: String
    let name: String
    let rating: Double
    let priceLevel: String
    let imageUrl: String?
    let latitude: Double
    let longitude: Double
    // New optional fields (Req 15, 16, 19.5)
    let ratingSource: String?
    let reviewCount: Int?
    let priceRangeMin: Double?
    let priceRangeMax: Double?

    var id: String { placeId }

    // Custom init for backward compatibility — all new fields default to nil
    init(placeId: String, name: String, rating: Double, priceLevel: String, imageUrl: String?, latitude: Double, longitude: Double, ratingSource: String? = nil, reviewCount: Int? = nil, priceRangeMin: Double? = nil, priceRangeMax: Double? = nil) {
        self.placeId = placeId
        self.name = name
        self.rating = rating
        self.priceLevel = priceLevel
        self.imageUrl = imageUrl
        self.latitude = latitude
        self.longitude = longitude
        self.ratingSource = ratingSource
        self.reviewCount = reviewCount
        self.priceRangeMin = priceRangeMin
        self.priceRangeMax = priceRangeMax
    }
}

/// Response wrapper for place recommendations from `GET /places/hotels` and `GET /places/restaurants`.
/// Validates: Requirements 7.1, 7.2, 7.5
struct PlacesResponse: Codable {
    let results: [PlaceRecommendation]
    let filtersBroadened: Bool
}

// MARK: - Trip Save Request

/// Request body for `POST /trips` — save a trip.
/// Validates: Requirement 9.1
struct TripSaveRequest: Encodable {
    let destination: String
    let destinationLatLng: String?
    let numDays: Int
    let vibe: String?
    let preferences: [String: AnyCodableValue]?
    let itinerary: [String: AnyCodableValue]?
    let selectedHotelId: String?
    let selectedRestaurants: [[String: AnyCodableValue]]?
    let costBreakdown: [String: AnyCodableValue]?
}

/// A type-erased Codable value for encoding arbitrary JSON dictionaries.
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

/// Full trip response from `GET /trips/{id}` and `POST /trips`.
/// Validates: Requirements 9.1, 9.3
struct TripResponse: Codable, Identifiable {
    let id: String
    let userId: String
    let destination: String
    let destinationLatLng: String?
    let numDays: Int
    let vibe: String?
    let preferences: [String: AnyCodableValue]?
    let itinerary: [String: AnyCodableValue]?
    let selectedHotelId: String?
    let selectedRestaurants: [[String: AnyCodableValue]]?
    let costBreakdown: [String: AnyCodableValue]?
    let createdAt: String
    let updatedAt: String
}

/// Lightweight trip summary from `GET /trips`.
/// Validates: Requirement 9.2
struct TripListItem: Codable, Identifiable {
    let id: String
    let destination: String
    let numDays: Int
    let vibe: String?
    let createdAt: String
}

// MARK: - Share Models

/// Response from `POST /trips/{id}/share`.
/// Validates: Requirement 10.1
struct ShareLinkResponse: Codable {
    let shareId: String
    let shareUrl: String
}

/// Read-only trip data from `GET /share/{share_id}`.
/// Validates: Requirements 10.2, 10.3, 10.4
struct SharedTripResponse: Codable {
    let destination: String
    let destinationLatLng: String?
    let numDays: Int
    let vibe: String?
    let itinerary: [String: AnyCodableValue]?
    let selectedHotelId: String?
    let selectedRestaurants: [[String: AnyCodableValue]]?
    let costBreakdown: [String: AnyCodableValue]?
}

// MARK: - Cost Request

/// Request body for `POST /trips/cost`.
/// Validates: Requirements 8.1, 8.2, 8.3
struct CostRequest: Encodable {
    let numDays: Int
    let hotelNightlyRate: Double
    let restaurantPriceRange: String
    let days: [CostRequestDay]
}

struct CostRequestDay: Encodable {
    let dayNumber: Int
    let activities: [ActivityCostItem]
}

struct ActivityCostItem: Encodable {
    let activityName: String
    let estimatedCostUsd: Double
}
