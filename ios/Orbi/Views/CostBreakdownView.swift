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
    var itinerary: ItineraryResponse? = nil

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
                if let itinerary = itinerary {
                    itemizedSection(itinerary: itinerary, cost: cost)
                } else {
                    perDaySection(cost: cost)
                }
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

    // MARK: - Itemized Breakdown

    private func itemizedSection(itinerary: ItineraryResponse, cost: CostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Itemized Breakdown")
                .font(.subheadline.weight(.semibold))

            // Hotel line (if we have a nightly rate)
            if cost.hotelTotal > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                    Text("Hotel (\(itinerary.numDays) nights)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Text("$\(Int(cost.hotelTotal))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    if cost.hotelIsEstimated == true {
                        Text("est.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(itinerary.days) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day \(day.dayNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DesignTokens.textSecondary)

                    ForEach(day.slots) { slot in
                        itemRow(
                            icon: "figure.walk",
                            name: slot.activityName,
                            timeSlot: slot.timeSlot,
                            cost: slot.estimatedCostUsd,
                            isEstimated: false
                        )
                    }

                    ForEach(day.meals) { meal in
                        itemRow(
                            icon: "fork.knife",
                            name: "\(meal.mealType): \(meal.restaurantName)",
                            timeSlot: meal.mealType,
                            cost: meal.estimatedCostUsd,
                            isEstimated: meal.isEstimated,
                            perPerson: true
                        )
                    }

                    // Day subtotal
                    let dayActivities = day.slots.reduce(0.0) { $0 + ($1.estimatedCostUsd ?? 0) }
                    let dayFood = day.meals.reduce(0.0) { $0 + ($1.estimatedCostUsd ?? 0) }
                    let dayHotel = cost.perDay.first(where: { $0.day == day.dayNumber })?.hotel ?? 0
                    let dayTotal = dayActivities + dayFood + dayHotel

                    HStack {
                        Spacer()
                        Text("Day \(day.dayNumber) subtotal: $\(Int(dayTotal))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func itemRow(icon: String, name: String, timeSlot: String, cost: Double?, isEstimated: Bool, perPerson: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.orange)
                .frame(width: 16)
            Text(name)
                .font(.caption)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Spacer()
            if let cost = cost, cost > 0 {
                Text("$\(Int(cost))\(perPerson ? "/pp" : "")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                if isEstimated {
                    Text("est.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Free")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
        .padding(.vertical, 2)
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
