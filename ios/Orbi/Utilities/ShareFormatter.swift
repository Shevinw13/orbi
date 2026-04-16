import Foundation

// MARK: - Share Formatter

/// Formats trip itinerary data into human-readable plain text for sharing.
/// Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5
struct ShareFormatter {

    static func formatTrip(
        _ itinerary: ItineraryResponse,
        plannedBy: String? = nil,
        notes: String? = nil,
        hotel: PlaceRecommendation? = nil
    ) -> String {
        var lines: [String] = []
        var totalCost: Double = 0
        var hasCostData = false

        // Title line
        let vibesStr = itinerary.vibes.joined(separator: " & ")
        lines.append("\(itinerary.numDays)-Day \(itinerary.destination) \(vibesStr) Trip")

        if let plannedBy = plannedBy?.trimmingCharacters(in: .whitespacesAndNewlines), !plannedBy.isEmpty {
            lines.append("Planned by \(plannedBy)")
        }

        // Hotel info
        if let hotel = hotel {
            let price = PriceFormatter.hotelPrice(min: hotel.priceRangeMin, max: hotel.priceRangeMax, tier: hotel.priceLevel)
            lines.append("Hotel: \(hotel.name) (\(price))")
        }

        lines.append("")

        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("Notes:")
            lines.append(notes)
            lines.append("")
        }

        for day in itinerary.days {
            lines.append("Day \(day.dayNumber):")

            if day.slots.isEmpty && day.meals.isEmpty {
                lines.append("  No activities planned")
            } else {
                for slot in day.slots {
                    if let cost = slot.estimatedCostUsd, cost > 0 {
                        lines.append("  \(slot.activityName) (\(slot.timeSlot)) ($\(Int(cost)))")
                        totalCost += cost
                        hasCostData = true
                    } else {
                        lines.append("  \(slot.activityName) (\(slot.timeSlot))")
                    }
                }

                for meal in day.meals {
                    let costStr = meal.estimatedCostUsd.map { $0 > 0 ? " ($\(Int($0)))" : "" } ?? ""
                    lines.append("  🍽 \(meal.restaurantName) - \(meal.cuisine) (\(meal.mealType))\(costStr)")
                    if let cost = meal.estimatedCostUsd, cost > 0 {
                        totalCost += cost
                        hasCostData = true
                    }
                }
            }

            lines.append("")
        }

        if itinerary.days.isEmpty {
            lines.append("No activities planned")
            lines.append("")
        }

        if hasCostData {
            lines.append("Estimated Total: $\(Int(totalCost))")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
