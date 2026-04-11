import Foundation

// MARK: - Share Formatter

/// Formats trip itinerary data into human-readable plain text for sharing.
/// Validates: Requirements 14.1, 14.2, 14.3, 14.4, 14.5
struct ShareFormatter {

    /// Formats an itinerary response into plain text suitable for iMessage, Email, and Notes.
    /// - Parameter itinerary: The itinerary to format.
    /// - Returns: A plain text string with title, day-by-day breakdown, and restaurant names.
    static func formatTrip(_ itinerary: ItineraryResponse) -> String {
        var lines: [String] = []

        // Title line (Req 14.2)
        lines.append("\(itinerary.numDays)-Day \(itinerary.destination) \(itinerary.vibe) Trip")
        lines.append("")

        // Day-by-day breakdown (Req 14.3, 14.4)
        for day in itinerary.days {
            lines.append("Day \(day.dayNumber):")

            if day.slots.isEmpty {
                lines.append("  No activities planned")
            } else {
                for slot in day.slots {
                    lines.append("  \(slot.activityName) (\(slot.timeSlot))")
                }
            }

            // Restaurant name (Req 14.4)
            if let restaurant = day.restaurant {
                lines.append("  🍽 \(restaurant.name)")
            }

            lines.append("")
        }

        // Handle empty itinerary
        if itinerary.days.isEmpty {
            lines.append("No activities planned")
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
