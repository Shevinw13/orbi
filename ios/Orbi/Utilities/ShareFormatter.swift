import Foundation

// MARK: - Share Formatter

/// Formats trip itinerary data into human-readable plain text for sharing.
/// Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5
struct ShareFormatter {

    /// Formats an itinerary response into plain text suitable for iMessage, Email, and Notes.
    /// Includes activity costs, restaurant cuisine details, and a total estimated cost.
    /// - Parameters:
    ///   - itinerary: The itinerary to format.
    ///   - plannedBy: Optional planner name to include below the title.
    ///   - notes: Optional notes to include after the title block.
    /// - Returns: A plain text string with title, day-by-day breakdown, restaurant details, and total cost.
    static func formatTrip(
        _ itinerary: ItineraryResponse,
        plannedBy: String? = nil,
        notes: String? = nil
    ) -> String {
        var lines: [String] = []
        var totalCost: Double = 0
        var hasCostData = false

        // Title line (Req 13.1)
        lines.append("\(itinerary.numDays)-Day \(itinerary.destination) \(itinerary.vibe) Trip")

        // Planned by line (Req 5.2, 5.3)
        if let plannedBy = plannedBy?.trimmingCharacters(in: .whitespacesAndNewlines), !plannedBy.isEmpty {
            lines.append("Planned by \(plannedBy)")
        }

        lines.append("")

        // Notes section (Req 5.4, 5.5)
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("Notes:")
            lines.append(notes)
            lines.append("")
        }

        // Day-by-day breakdown (Req 13.2, 13.5)
        for day in itinerary.days {
            lines.append("Day \(day.dayNumber):")

            if day.slots.isEmpty {
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
            }

            // Restaurant with cuisine type (Req 13.5)
            if let restaurant = day.restaurant {
                lines.append("  🍽 \(restaurant.name) - \(restaurant.cuisine) (\(restaurant.priceLevel))")
            }

            lines.append("")
        }

        // Handle empty itinerary
        if itinerary.days.isEmpty {
            lines.append("No activities planned")
            lines.append("")
        }

        // Total estimated cost line (Req 13.3)
        if hasCostData {
            lines.append("Estimated Total: $\(Int(totalCost))")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
