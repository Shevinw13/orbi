import SwiftUI

// MARK: - Food & Drinks View

/// Displays all meals from the itinerary grouped by day and time block.
/// Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5
struct FoodDrinksView: View {

    @ObservedObject var itineraryVM: ItineraryViewModel
    let budgetTier: String
    let vibes: [String]

    @State private var searchQuery: String = ""
    @State private var searchResults: [PlaceRecommendation] = []
    @State private var isSearching: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
                // Header
                HStack {
                    Label("Food & Drinks", systemImage: "fork.knife")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.spacingMD)

                // Search at top
                searchSection
                    .padding(.horizontal, DesignTokens.spacingMD)

                // Meals grouped by day
                ForEach(itineraryVM.itinerary.days) { day in
                    if !day.meals.isEmpty {
                        dayMealsSection(day: day)
                    }
                }

                if itineraryVM.itinerary.days.allSatisfy({ $0.meals.isEmpty }) {
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 36))
                            .foregroundStyle(DesignTokens.textSecondary)
                        Text("No meals in your itinerary yet")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                        Text("Add meals from the Itinerary tab")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.spacingXL)
                }

            }
            .padding(.vertical, DesignTokens.spacingMD)
        }
        .background(DesignTokens.backgroundPrimary)
        .sheet(isPresented: $itineraryVM.showReplaceSuggestions) {
            mealSuggestionsSheet
        }
    }

    private func dayMealsSection(day: ItineraryDay) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Text("Day \(day.dayNumber)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, DesignTokens.spacingMD)

            let blocks = ["Morning", "Afternoon", "Evening"]
            let mealTypeMap = ["Morning": "Breakfast", "Afternoon": "Lunch", "Evening": "Dinner"]

            ForEach(blocks, id: \.self) { block in
                let blockMeals = day.meals.filter { meal in
                    let mealBlock: String
                    switch meal.mealType.lowercased() {
                    case "breakfast": mealBlock = "Morning"
                    case "lunch": mealBlock = "Afternoon"
                    case "dinner": mealBlock = "Evening"
                    default: mealBlock = "Morning"
                    }
                    return mealBlock == block
                }

                if !blockMeals.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                        Text(mealTypeMap[block] ?? block)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(timeSlotColor(block))
                            .padding(.horizontal, DesignTokens.spacingMD)

                        ForEach(blockMeals) { meal in
                            mealCard(meal: meal, dayNumber: day.dayNumber)
                                .padding(.horizontal, DesignTokens.spacingMD)
                        }
                    }
                }
            }
        }
    }

    private func mealCard(meal: MealSlot, dayNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(DesignTokens.accentCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.restaurantName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    HStack(spacing: 6) {
                        if !meal.cuisine.isEmpty {
                            Text(meal.cuisine)
                        }
                        Text(meal.priceLevel)
                        if let cost = meal.estimatedCostUsd, cost > 0 {
                            Text("~$\(Int(cost))/person")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                if meal.isEstimated {
                    Text("Est. per person")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }

            // Replace action
            HStack(spacing: 16) {
                Button {
                    Task {
                        await itineraryVM.replaceMeal(dayNumber: dayNumber, meal: meal)
                    }
                } label: {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.accentCyan)
                }
                .disabled(itineraryVM.isReplacing)

                Button(role: .destructive) {
                    itineraryVM.removeMeal(from: dayNumber, meal: meal)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption2)
                }
            }
        }
        .padding(DesignTokens.spacingSM)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
    }

    @ViewBuilder
    private var mealSuggestionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.spacingSM) {
                    ForEach(itineraryVM.mealReplaceSuggestions) { suggestion in
                        Button {
                            itineraryVM.selectMealReplacement(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.restaurantName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                HStack(spacing: 8) {
                                    Text(suggestion.cuisine)
                                    Text(suggestion.priceLevel)
                                    if let cost = suggestion.estimatedCostUsd, cost > 0 {
                                        Text("~$\(Int(cost))")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textTertiary)
                            }
                            .padding(DesignTokens.spacingSM)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DesignTokens.spacingMD)
            }
            .background(DesignTokens.backgroundPrimary)
            .navigationTitle("Pick a Restaurant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Text("Search Restaurants")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.textTertiary)
                TextField("Search by cuisine or name...", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .onSubmit { Task { await searchRestaurants() } }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.textTertiary)
                    }
                }
                if isSearching {
                    ProgressView().controlSize(.small).tint(DesignTokens.accentCyan)
                }
            }
            .padding(DesignTokens.spacingSM)
            .glassmorphic(cornerRadius: DesignTokens.radiusSM)
            .onChange(of: searchQuery) { _, newValue in
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard searchQuery == newValue else { return }
                    await searchRestaurants()
                }
            }

            if !searchResults.isEmpty {
                Text("Results for \"\(searchQuery)\"")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accentCyan)

                ForEach(searchResults) { result in
                    searchResultCard(result)
                }
            } else if !searchQuery.isEmpty && !isSearching {
                Text("No results found")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textTertiary)
            }
        }
    }

    private func searchRestaurants() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { searchResults = []; return }
        isSearching = true
        // Get coordinates from first day's first meal or slot
        let lat = itineraryVM.itinerary.days.first?.meals.first?.latitude
            ?? itineraryVM.itinerary.days.first?.slots.first?.latitude ?? 0
        let lng = itineraryVM.itinerary.days.first?.meals.first?.longitude
            ?? itineraryVM.itinerary.days.first?.slots.first?.longitude ?? 0
        let queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lng)),
            URLQueryItem(name: "cuisine", value: query),
        ]
        do {
            let response: PlacesResponse = try await APIClient.shared.request(
                .get, path: "/places/restaurants", queryItems: queryItems
            )
            searchResults = response.results
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    private func searchResultCard(_ place: PlaceRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            HStack(spacing: 6) {
                if place.rating > 0 {
                    Label(String(format: "%.1f", place.rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                Text(place.formattedRestaurantPrice)
                    .foregroundStyle(DesignTokens.accentCyan)
            }
            .font(.caption)
        }
        .padding(DesignTokens.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
    }

    private func timeSlotColor(_ block: String) -> Color {
        switch block.lowercased() {
        case "morning": return DesignTokens.accentCyan
        case "afternoon": return DesignTokens.accentBlue
        case "evening": return .purple
        default: return .gray
        }
    }
}
