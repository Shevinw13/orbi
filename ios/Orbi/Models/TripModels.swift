import Foundation

// MARK: - Budget Tier

/// Unified 5-tier budget selector replacing PriceRange + HotelVibe.
/// Validates: Requirements 2.1, 2.2, 2.3
enum BudgetTier: String, CaseIterable, Identifiable, Codable {
    case budget = "budget"
    case casual = "casual"
    case comfortable = "comfortable"
    case premium = "premium"
    case luxury = "luxury"

    var id: String { rawValue }

    /// Dollar-sign display string sent to the API.
    var apiValue: String {
        switch self {
        case .budget: return "$"
        case .casual: return "$$"
        case .comfortable: return "$$$"
        case .premium: return "$$$$"
        case .luxury: return "$$$$$"
        }
    }

    var label: String {
        switch self {
        case .budget: return "Budget"
        case .casual: return "Casual"
        case .comfortable: return "Comfortable"
        case .premium: return "Premium"
        case .luxury: return "Luxury"
        }
    }
}

// MARK: - Meal Slot

/// A meal entry (Breakfast, Lunch, or Dinner) placed within a time block.
/// Validates: Requirements 5.4, 13.3
struct MealSlot: Codable, Identifiable, Equatable {
    var mealType: String
    var restaurantName: String
    var cuisine: String
    var priceLevel: String
    var latitude: Double
    var longitude: Double
    var estimatedCostUsd: Double?
    var placeId: String?
    var isEstimated: Bool

    var id: String { "\(mealType)-\(restaurantName)" }

    static func == (lhs: MealSlot, rhs: MealSlot) -> Bool {
        lhs.mealType == rhs.mealType && lhs.restaurantName == rhs.restaurantName
    }
}

// MARK: - Trip Preferences Request

/// Preferences payload sent to `POST /trips/generate`.
/// Validates: Requirements 2.5, 3.6
struct TripPreferencesRequest: Encodable {
    let destination: String
    let latitude: Double
    let longitude: Double
    let numDays: Int
    let budgetTier: String
    let vibes: [String]
    let familyFriendly: Bool
}

// MARK: - Itinerary Response

/// Top-level itinerary returned from `POST /trips/generate`.
struct ItineraryResponse: Codable {
    let destination: String
    let numDays: Int
    let vibes: [String]
    let budgetTier: String
    var days: [ItineraryDay]
    var reasoningText: String?
}

/// Represents a single item in a time block — either an activity or a meal.
enum TimeBlockItem: Identifiable {
    case activity(ItinerarySlot)
    case meal(MealSlot)

    var id: String {
        switch self {
        case .activity(let slot): return "activity-\(slot.id)"
        case .meal(let meal): return "meal-\(meal.id)"
        }
    }

    /// The time block this item belongs to (Morning, Afternoon, Evening).
    var timeBlock: String {
        switch self {
        case .activity(let slot): return slot.timeSlot
        case .meal(let meal):
            switch meal.mealType.lowercased() {
            case "breakfast": return "Morning"
            case "lunch": return "Afternoon"
            case "dinner": return "Evening"
            default: return "Morning"
            }
        }
    }

    /// Sort order: Morning=0, Afternoon=1, Evening=2. Within a block, activities before meals.
    var sortOrder: Int {
        let blockOrder: Int
        switch timeBlock.lowercased() {
        case "morning": blockOrder = 0
        case "afternoon": blockOrder = 1
        case "evening": blockOrder = 2
        default: blockOrder = 3
        }
        // Activities sort before meals within the same block
        let typeOrder: Int
        switch self {
        case .activity: typeOrder = 0
        case .meal: typeOrder = 1
        }
        return blockOrder * 10 + typeOrder
    }
}

struct ItineraryDay: Codable, Identifiable {
    let dayNumber: Int
    var slots: [ItinerarySlot]
    var meals: [MealSlot]

    var id: Int { dayNumber }

    /// All items merged in chronological order (Morning → Afternoon → Evening; activities then meals within each block).
    var timeBlockItems: [TimeBlockItem] {
        var items: [TimeBlockItem] = []
        items.append(contentsOf: slots.map { .activity($0) })
        items.append(contentsOf: meals.map { .meal($0) })
        return items.sorted { $0.sortOrder < $1.sortOrder }
    }

    init(dayNumber: Int, slots: [ItinerarySlot], meals: [MealSlot] = []) {
        self.dayNumber = dayNumber
        self.slots = slots
        self.meals = meals
    }
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
    var tag: String?

    var id: String { "\(timeSlot)-\(activityName)" }

    static func == (lhs: ItinerarySlot, rhs: ItinerarySlot) -> Bool {
        lhs.timeSlot == rhs.timeSlot && lhs.activityName == rhs.activityName
    }
}

/// Kept for backward compatibility with saved trips that may still have this field.
struct ItineraryRestaurant: Codable {
    let name: String
    let cuisine: String
    let priceLevel: String
    let rating: Double
    let latitude: Double
    let longitude: Double
    let imageUrl: String?
    let origin: String?
}

// MARK: - Replace Activity

/// Request body for `POST /trips/replace-item`.
/// Validates: Requirement 6.2, 14.1, 14.2
struct ReplaceActivityRequest: Encodable {
    let destination: String
    let dayNumber: Int
    let timeSlot: String
    let itemType: String
    let currentItemName: String
    let existingActivities: [String]
    let vibes: [String]
    let budgetTier: String
    let adjacentActivityCoords: [[String: Double]]?
    let numSuggestions: Int
}

/// Response from `POST /trips/replace-item` with multiple suggestions.
struct ReplaceSuggestionsResponse: Codable {
    let suggestions: [ItinerarySlot]
}

/// Response for meal replacement suggestions.
struct MealReplaceSuggestionsResponse: Codable {
    let suggestions: [MealSlot]
}

// MARK: - Cost Breakdown

/// Cost breakdown returned by the Cost_Estimator.
/// Validates: Requirements 8.1, 8.2, 8.3, 8.4, 9.3
struct CostBreakdown: Codable {
    let hotelTotal: Double
    let hotelIsEstimated: Bool?
    let foodTotal: Double
    let foodIsEstimated: Bool?
    let activitiesTotal: Double
    let total: Double
    let perDay: [DayCost]
}

struct DayCost: Codable, Identifiable {
    let day: Int
    let hotel: Double
    let hotelIsEstimated: Bool?
    let food: Double
    let foodIsEstimated: Bool?
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
    let ratingSource: String?
    let reviewCount: Int?
    let priceRangeMin: Double?
    let priceRangeMax: Double?

    var id: String { placeId }

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

    private var priceTier: Int {
        let dollarCount = priceLevel.filter { $0 == "$" }.count
        if dollarCount <= 1 { return 1 }
        if dollarCount == 2 { return 2 }
        return 3
    }

    var formattedHotelPrice: String {
        if let min = priceRangeMin, let max = priceRangeMax, min > 0, max > 0 {
            let avg = Int((min + max) / 2.0)
            return "$\(avg) / night avg"
        }
        let fallback: Int
        switch priceTier {
        case 1: fallback = 80
        case 3: fallback = 250
        default: fallback = 150
        }
        return "$\(fallback) / night avg"
    }

    var formattedRestaurantPrice: String {
        if let min = priceRangeMin, let max = priceRangeMax, min > 0, max > 0 {
            return "$\(Int(min))–$\(Int(max)) per person"
        }
        let low: Int
        let high: Int
        switch priceTier {
        case 1: low = 10; high = 20
        case 3: low = 40; high = 80
        default: low = 20; high = 40
        }
        return "$\(low)–$\(high) per person"
    }
}

/// Response wrapper for place recommendations.
struct PlacesResponse: Codable {
    let results: [PlaceRecommendation]
    let filtersBroadened: Bool
}

// MARK: - Trip Save Request

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
    let copiedFromSharedId: String?
    let originalCreatorUsername: String?
    let createdAt: String
    let updatedAt: String
}

struct TripListItem: Codable, Identifiable {
    let id: String
    let destination: String
    let numDays: Int
    let vibe: String?
    let createdAt: String
}

// MARK: - Share Models

struct ShareLinkResponse: Codable {
    let shareId: String
    let shareUrl: String
}

struct ShareCreateBody: Encodable {
    let plannedBy: String?
    let notes: String?
}

struct SharedTripResponse: Codable {
    let destination: String
    let destinationLatLng: String?
    let numDays: Int
    let vibe: String?
    let itinerary: [String: AnyCodableValue]?
    let selectedHotelId: String?
    let selectedRestaurants: [[String: AnyCodableValue]]?
    let costBreakdown: [String: AnyCodableValue]?
    let plannedBy: String?
    let notes: String?
}

// MARK: - Cost Request

struct CostRequest: Encodable {
    let numDays: Int
    let hotelNightlyRate: Double
    let restaurantPriceRange: String
    let days: [CostRequestDay]
    let hotelIsEstimated: Bool
    let foodIsEstimated: Bool
}

struct CostRequestDay: Encodable {
    let dayNumber: Int
    let activities: [ActivityCostItem]
}

struct ActivityCostItem: Encodable {
    let activityName: String
    let estimatedCostUsd: Double
}
