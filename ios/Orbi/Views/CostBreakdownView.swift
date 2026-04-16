import SwiftUI

// MARK: - Cost ViewModel

@MainActor
final class CostViewModel: ObservableObject {

    @Published var costBreakdown: CostBreakdown?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let itinerary: ItineraryResponse
    private let budgetTier: String

    private(set) var hotelNightlyRate: Double = 0
    private(set) var hotelIsEstimated: Bool = true

    init(itinerary: ItineraryResponse, budgetTier: String) {
        self.itinerary = itinerary
        self.budgetTier = budgetTier
    }

    func recalculate(hotelNightlyRate: Double, hotelIsEstimated: Bool = true) async {
        self.hotelNightlyRate = hotelNightlyRate
        self.hotelIsEstimated = hotelIsEstimated
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
            restaurantPriceRange: budgetTier,
            days: days,
            hotelIsEstimated: hotelIsEstimated,
            foodIsEstimated: true
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

    // MARK: - Total

    private func totalSection(cost: CostBreakdown) -> some View {
        VStack(spacing: 4) {
            Text("Estimated total cost")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("$\(Int(cost.total))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimated total trip cost: $\(Int(cost.total))")
    }

    // MARK: - Category Breakdown (Hotels, Food & Drinks, Activities)

    private func categoryBreakdown(cost: CostBreakdown) -> some View {
        HStack(spacing: 0) {
            categoryPill(icon: "building.2", label: "Hotels", amount: cost.hotelTotal, isEstimated: cost.hotelIsEstimated ?? true)
            Divider().frame(height: 40)
            categoryPill(icon: "fork.knife", label: "Food & Drinks", amount: cost.foodTotal, isEstimated: cost.foodIsEstimated ?? true)
            Divider().frame(height: 40)
            categoryPill(icon: "figure.walk", label: "Activities", amount: cost.activitiesTotal, isEstimated: false)
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func categoryPill(icon: String, label: String, amount: Double, isEstimated: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("$\(Int(amount))")
                .font(.subheadline.weight(.semibold))
            if isEstimated {
                Text("Estimated")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): $\(Int(amount))\(isEstimated ? ", estimated" : "")")
    }

    // MARK: - Per-Day Breakdown

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
                costLabel(icon: "building.2", amount: day.hotel, isEstimated: day.hotelIsEstimated ?? true)
                costLabel(icon: "fork.knife", amount: day.food, isEstimated: day.foodIsEstimated ?? true)
                costLabel(icon: "figure.walk", amount: day.activities, isEstimated: false)
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

    private func costLabel(icon: String, amount: Double, isEstimated: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("$\(Int(amount))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isEstimated && amount > 0 {
                Text("~")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let itinerary = ItineraryResponse(
        destination: "Tokyo",
        numDays: 3,
        vibes: ["Foodie"],
        budgetTier: "$$$",
        days: [
            ItineraryDay(dayNumber: 1, slots: [
                ItinerarySlot(timeSlot: "Morning", activityName: "Tsukiji Market", description: "Fresh seafood", latitude: 35.66, longitude: 139.77, estimatedDurationMin: 120, travelTimeToNextMin: 15, estimatedCostUsd: 20),
            ], meals: []),
        ]
    )
    let vm = CostViewModel(itinerary: itinerary, budgetTier: "$$$")
    vm.costBreakdown = CostBreakdown(
        hotelTotal: 450,
        hotelIsEstimated: true,
        foodTotal: 180,
        foodIsEstimated: false,
        activitiesTotal: 50,
        total: 680,
        perDay: [
            DayCost(day: 1, hotel: 150, hotelIsEstimated: true, food: 60, foodIsEstimated: false, activities: 20, subtotal: 230),
            DayCost(day: 2, hotel: 150, hotelIsEstimated: true, food: 60, foodIsEstimated: false, activities: 0, subtotal: 210),
            DayCost(day: 3, hotel: 150, hotelIsEstimated: true, food: 60, foodIsEstimated: false, activities: 30, subtotal: 240),
        ]
    )
    return NavigationStack {
        ScrollView {
            CostBreakdownView(viewModel: vm)
        }
        .navigationTitle("Trip Cost")
    }
}
