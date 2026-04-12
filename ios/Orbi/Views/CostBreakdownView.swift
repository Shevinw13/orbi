import SwiftUI

// MARK: - Cost ViewModel

/// Manages cost estimation state, auto-recalculation on itinerary/hotel changes.
/// Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5
@MainActor
final class CostViewModel: ObservableObject {

    @Published var costBreakdown: CostBreakdown?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let itinerary: ItineraryResponse
    private let restaurantPriceRange: String

    /// Currently selected hotel nightly rate, updated when hotel selection changes (Req 8.5).
    private(set) var hotelNightlyRate: Double = 0

    init(itinerary: ItineraryResponse, restaurantPriceRange: String) {
        self.itinerary = itinerary
        self.restaurantPriceRange = restaurantPriceRange
    }

    // MARK: - Recalculate (Req 8.5)

    /// Called when itinerary or hotel selection changes.
    func recalculate(hotelNightlyRate: Double) async {
        self.hotelNightlyRate = hotelNightlyRate
        isLoading = true
        errorMessage = nil

        let days = itinerary.days.map { day in
            CostRequestDay(
                dayNumber: day.dayNumber,
                activities: day.slots.map { slot in
                    ActivityCostItem(
                        activityName: slot.activityName,
                        estimatedCostUsd: slot.estimatedCostUsd ?? 0
                    )
                }
            )
        }

        let request = CostRequest(
            numDays: itinerary.numDays,
            hotelNightlyRate: hotelNightlyRate,
            restaurantPriceRange: restaurantPriceRange,
            days: days
        )

        do {
            let breakdown: CostBreakdown = try await APIClient.shared.request(
                .post, path: "/trips/cost", body: request
            )
            costBreakdown = breakdown
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to calculate costs. Please try again."
        }

        isLoading = false
    }
}


// MARK: - Cost Breakdown View

/// Displays total estimated trip cost and per-day breakdown.
/// Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5
struct CostBreakdownView: View {

    @ObservedObject var viewModel: CostViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Calculating costs…")
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            } else if let cost = viewModel.costBreakdown {
                totalSection(cost: cost)
                categoryBreakdown(cost: cost)
                perDaySection(cost: cost)
            } else {
                Text("Select a hotel to see cost estimates")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }
        }
        .padding(16)
    }

    // MARK: - Total (Req 8.4)

    private func totalSection(cost: CostBreakdown) -> some View {
        VStack(spacing: 4) {
            Text("Estimated total cost")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("$\(Int(cost.total))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
            Text("Based on average prices")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimated total trip cost: $\(Int(cost.total)). Based on average prices.")
    }

    // MARK: - Category Breakdown (Req 8.1, 8.2, 8.3)

    private func categoryBreakdown(cost: CostBreakdown) -> some View {
        HStack(spacing: 0) {
            categoryPill(icon: "building.2", label: "Hotel", amount: cost.hotelTotal)
            Divider().frame(height: 40)
            categoryPill(icon: "fork.knife", label: "Food", amount: cost.foodTotal)
            Divider().frame(height: 40)
            categoryPill(icon: "figure.walk", label: "Activities", amount: cost.activitiesTotal)
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func categoryPill(icon: String, label: String, amount: Double) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("$\(Int(amount))")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): $\(Int(amount))")
    }

    // MARK: - Per-Day Breakdown (Req 8.4)

    private func perDaySection(cost: CostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Day Breakdown")
                .font(.subheadline.weight(.semibold))

            ForEach(cost.perDay) { day in
                dayRow(day: day)
            }
        }
    }

    private func dayRow(day: DayCost) -> some View {
        HStack {
            Text("Day \(day.day)")
                .font(.subheadline.weight(.medium))

            Spacer()

            HStack(spacing: 12) {
                costLabel(icon: "building.2", amount: day.hotel)
                costLabel(icon: "fork.knife", amount: day.food)
                costLabel(icon: "figure.walk", amount: day.activities)
            }

            Text("$\(Int(day.subtotal))")
                .font(.subheadline.weight(.semibold))
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(day.day): hotel $\(Int(day.hotel)), food $\(Int(day.food)), activities $\(Int(day.activities)), subtotal $\(Int(day.subtotal))")
    }

    private func costLabel(icon: String, amount: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("$\(Int(amount))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    let itinerary = ItineraryResponse(
        destination: "Tokyo",
        numDays: 3,
        vibe: "Foodie",
        days: [
            ItineraryDay(dayNumber: 1, slots: [
                ItinerarySlot(timeSlot: "Morning", activityName: "Tsukiji Market", description: "Fresh seafood", latitude: 35.66, longitude: 139.77, estimatedDurationMin: 120, travelTimeToNextMin: 15, estimatedCostUsd: 20),
            ], restaurant: nil),
            ItineraryDay(dayNumber: 2, slots: [
                ItinerarySlot(timeSlot: "Morning", activityName: "Meiji Shrine", description: "Peaceful shrine", latitude: 35.67, longitude: 139.69, estimatedDurationMin: 90, travelTimeToNextMin: 10, estimatedCostUsd: 0),
            ], restaurant: nil),
            ItineraryDay(dayNumber: 3, slots: [
                ItinerarySlot(timeSlot: "Morning", activityName: "Akihabara", description: "Electronics district", latitude: 35.70, longitude: 139.77, estimatedDurationMin: 120, travelTimeToNextMin: nil, estimatedCostUsd: 30),
            ], restaurant: nil),
        ]
    )
    let vm = CostViewModel(itinerary: itinerary, restaurantPriceRange: "$$")
    vm.costBreakdown = CostBreakdown(
        hotelTotal: 450,
        foodTotal: 180,
        activitiesTotal: 50,
        total: 680,
        perDay: [
            DayCost(day: 1, hotel: 150, food: 60, activities: 20, subtotal: 230),
            DayCost(day: 2, hotel: 150, food: 60, activities: 0, subtotal: 210),
            DayCost(day: 3, hotel: 150, food: 60, activities: 30, subtotal: 240),
        ]
    )
    return NavigationStack {
        ScrollView {
            CostBreakdownView(viewModel: vm)
        }
        .navigationTitle("Trip Cost")
    }
}
