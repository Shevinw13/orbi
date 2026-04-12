import Foundation

/// Pure formatting utility for converting price data into human-readable strings.
/// Validates: Requirements 4.1, 4.3, 4.4, 4.5, 5.1, 5.3, 5.4, 5.5, 6.1, 6.2
enum PriceFormatter {

    // MARK: - Hotel Pricing

    /// Formats hotel pricing as "$XXX / night avg".
    /// Uses average of min/max when available, otherwise falls back to tier.
    static func hotelPrice(min: Double?, max: Double?, tier: String) -> String {
        if let min = min, let max = max, min > 0, max > 0 {
            let avg = Int((min + max) / 2.0)
            return "$\(avg) / night avg"
        }
        let fallback = hotelFallback(for: tier)
        return "$\(fallback) / night avg"
    }

    // MARK: - Restaurant Pricing

    /// Formats restaurant pricing as "$XX–$XX per person".
    /// Uses min/max directly when available, otherwise falls back to tier.
    static func restaurantPrice(min: Double?, max: Double?, tier: String) -> String {
        if let min = min, let max = max, min > 0, max > 0 {
            return "$\(Int(min))–$\(Int(max)) per person"
        }
        let (low, high) = restaurantFallback(for: tier)
        return "$\(low)–$\(high) per person"
    }

    /// Formats restaurant pricing from a tier string only (for itinerary rows).
    static func restaurantPriceFromTier(_ tier: String) -> String {
        let (low, high) = restaurantFallback(for: tier)
        return "$\(low)–$\(high) per person"
    }

    // MARK: - Private Helpers

    private static func priceTier(from tier: String) -> Int {
        let dollarCount = tier.filter { $0 == "$" }.count
        if dollarCount <= 1 { return 1 }
        if dollarCount == 2 { return 2 }
        return 3
    }

    private static func hotelFallback(for tier: String) -> Int {
        switch priceTier(from: tier) {
        case 1: return 80
        case 3: return 250
        default: return 150
        }
    }

    private static func restaurantFallback(for tier: String) -> (Int, Int) {
        switch priceTier(from: tier) {
        case 1: return (10, 20)
        case 3: return (40, 70)
        default: return (20, 40)
        }
    }
}
