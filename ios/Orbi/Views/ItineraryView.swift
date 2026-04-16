import SwiftUI
import UIKit
import MapKit

// MARK: - Itinerary ViewModel

@MainActor
final class ItineraryViewModel: ObservableObject {

    @Published var itinerary: ItineraryResponse
    @Published var selectedSlot: ItinerarySlot?
    @Published var showDetail: Bool = false
    @Published var showAddActivity: Bool = false
    @Published var addActivityDayNumber: Int = 1
    @Published var addActivityTimeSlot: String = "Morning"
    @Published var isReplacing: Bool = false
    @Published var errorMessage: String?
    @Published var estimatedCost: CostBreakdown?
    @Published var replaceSuggestions: [ItinerarySlot] = []
    @Published var mealReplaceSuggestions: [MealSlot] = []
    @Published var showReplaceSuggestions: Bool = false
    @Published var replaceTargetDay: Int = 0
    @Published var replaceTargetSlot: ItinerarySlot?
    @Published var replaceTargetMeal: MealSlot?

    @Published var draggingSlot: ItinerarySlot?
    @Published var draggingFromDay: Int?

    private var didFireReplaceHaptic: Bool = false

    init(itinerary: ItineraryResponse) {
        self.itinerary = itinerary
        autoOptimizeAllDays()
    }

    private func autoOptimizeAllDays() {
        for day in itinerary.days where day.slots.count >= 3 {
            optimizeDay(day.dayNumber)
        }
    }

    // MARK: - Reorder

    func moveSlot(in dayNumber: Int, from source: IndexSet, to destination: Int) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        itinerary.days[dayIndex].slots.move(fromOffsets: source, toOffset: destination)
        recalculateCost()
    }

    func moveSlotToDay(_ slot: ItinerarySlot, fromDay: Int, toDay: Int) {
        guard fromDay != toDay else { return }
        guard let fromIndex = itinerary.days.firstIndex(where: { $0.dayNumber == fromDay }),
              let toIndex = itinerary.days.firstIndex(where: { $0.dayNumber == toDay }) else { return }
        guard let slotIndex = itinerary.days[fromIndex].slots.firstIndex(where: { $0 == slot }) else { return }
        let movedSlot = itinerary.days[fromIndex].slots.remove(at: slotIndex)
        itinerary.days[toIndex].slots.append(movedSlot)
        recalculateCost()
    }

    // MARK: - Replace activity (shows 3-5 suggestions)

    func replaceActivity(dayNumber: Int, slot: ItinerarySlot) async {
        isReplacing = true
        errorMessage = nil
        didFireReplaceHaptic = false

        let allActivities = itinerary.days.flatMap { $0.slots.map(\.activityName) }
        var adjacentCoords: [[String: Double]]?
        if let day = itinerary.days.first(where: { $0.dayNumber == dayNumber }),
           let slotIndex = day.slots.firstIndex(where: { $0 == slot }) {
            var coords: [[String: Double]] = []
            if slotIndex > 0 {
                let prev = day.slots[slotIndex - 1]
                coords.append(["lat": prev.latitude, "lng": prev.longitude])
            }
            if slotIndex < day.slots.count - 1 {
                let next = day.slots[slotIndex + 1]
                coords.append(["lat": next.latitude, "lng": next.longitude])
            }
            if !coords.isEmpty { adjacentCoords = coords }
        }

        let request = ReplaceActivityRequest(
            destination: itinerary.destination,
            dayNumber: dayNumber,
            timeSlot: slot.timeSlot,
            itemType: "activity",
            currentItemName: slot.activityName,
            existingActivities: allActivities,
            vibes: itinerary.vibes,
            budgetTier: itinerary.budgetTier,
            adjacentActivityCoords: adjacentCoords,
            numSuggestions: 5
        )

        do {
            let response: ReplaceSuggestionsResponse = try await APIClient.shared.request(
                .post, path: "/trips/replace-item", body: request
            )
            replaceSuggestions = response.suggestions
            replaceTargetDay = dayNumber
            replaceTargetSlot = slot
            replaceTargetMeal = nil
            showReplaceSuggestions = true
            if !didFireReplaceHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                didFireReplaceHaptic = true
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to get suggestions. Please try again."
        }
        isReplacing = false
    }

    func selectReplacement(_ newSlot: ItinerarySlot) {
        guard let targetSlot = replaceTargetSlot,
              let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == replaceTargetDay }),
              let slotIndex = itinerary.days[dayIndex].slots.firstIndex(where: { $0 == targetSlot }) else { return }
        itinerary.days[dayIndex].slots[slotIndex] = newSlot
        showReplaceSuggestions = false
        replaceSuggestions = []
        replaceTargetSlot = nil
        recalculateCost()
    }

    // MARK: - Replace meal (shows 3-5 suggestions)

    func replaceMeal(dayNumber: Int, meal: MealSlot) async {
        isReplacing = true
        errorMessage = nil

        let allMeals = itinerary.days.flatMap { $0.meals.map(\.restaurantName) }

        let request = ReplaceActivityRequest(
            destination: itinerary.destination,
            dayNumber: dayNumber,
            timeSlot: meal.mealType == "Breakfast" ? "Morning" : meal.mealType == "Lunch" ? "Afternoon" : "Evening",
            itemType: "meal",
            currentItemName: meal.restaurantName,
            existingActivities: allMeals,
            vibes: itinerary.vibes,
            budgetTier: itinerary.budgetTier,
            adjacentActivityCoords: nil,
            numSuggestions: 5
        )

        do {
            // Try to decode as meal suggestions first, fall back to activity suggestions
            let response: ReplaceSuggestionsResponse = try await APIClient.shared.request(
                .post, path: "/trips/replace-item", body: request
            )
            // Convert activity slots to meal slots for display
            mealReplaceSuggestions = response.suggestions.map { slot in
                MealSlot(
                    mealType: meal.mealType,
                    restaurantName: slot.activityName,
                    cuisine: "",
                    priceLevel: itinerary.budgetTier,
                    latitude: slot.latitude,
                    longitude: slot.longitude,
                    estimatedCostUsd: slot.estimatedCostUsd,
                    isEstimated: true
                )
            }
            replaceTargetDay = dayNumber
            replaceTargetMeal = meal
            replaceTargetSlot = nil
            showReplaceSuggestions = true
        } catch {
            errorMessage = "Failed to get meal suggestions."
        }
        isReplacing = false
    }

    func selectMealReplacement(_ newMeal: MealSlot) {
        guard let targetMeal = replaceTargetMeal,
              let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == replaceTargetDay }),
              let mealIndex = itinerary.days[dayIndex].meals.firstIndex(where: { $0 == targetMeal }) else { return }
        itinerary.days[dayIndex].meals[mealIndex] = newMeal
        showReplaceSuggestions = false
        mealReplaceSuggestions = []
        replaceTargetMeal = nil
        recalculateCost()
    }

    // MARK: - Add / Remove

    func addActivity(to dayNumber: Int, name: String, description: String, durationMin: Int, timeSlot: String) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        let newSlot = ItinerarySlot(
            timeSlot: timeSlot,
            activityName: name,
            description: description,
            latitude: 0,
            longitude: 0,
            estimatedDurationMin: durationMin,
            travelTimeToNextMin: nil,
            estimatedCostUsd: 0
        )
        itinerary.days[dayIndex].slots.append(newSlot)
        recalculateCost()
    }

    func removeActivity(from dayNumber: Int, slot: ItinerarySlot) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        itinerary.days[dayIndex].slots.removeAll { $0 == slot }
        recalculateCost()
    }

    func addMeal(to dayNumber: Int, mealType: String) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        let newMeal = MealSlot(
            mealType: mealType,
            restaurantName: "Choose a restaurant",
            cuisine: "",
            priceLevel: itinerary.budgetTier,
            latitude: 0,
            longitude: 0,
            estimatedCostUsd: 0,
            isEstimated: true
        )
        itinerary.days[dayIndex].meals.append(newMeal)
        recalculateCost()
    }

    func removeMeal(from dayNumber: Int, meal: MealSlot) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        itinerary.days[dayIndex].meals.removeAll { $0 == meal }
        recalculateCost()
    }

    // MARK: - Optimize Day

    func optimizeDay(_ dayNumber: Int) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        var slots = itinerary.days[dayIndex].slots
        guard slots.count >= 3 else { return }

        var remaining = Array(slots.dropFirst())
        var ordered = [slots[0]]

        while !remaining.isEmpty {
            let current = ordered.last!
            var nearestIndex = 0
            var nearestDist = Double.greatestFiniteMagnitude
            for (i, candidate) in remaining.enumerated() {
                let dist = haversineDistance(
                    lat1: current.latitude, lon1: current.longitude,
                    lat2: candidate.latitude, lon2: candidate.longitude
                )
                if dist < nearestDist {
                    nearestDist = dist
                    nearestIndex = i
                }
            }
            ordered.append(remaining.remove(at: nearestIndex))
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            itinerary.days[dayIndex].slots = ordered
        }
        recalculateTravelTimes(for: dayIndex)
        recalculateCost()
    }

    private func recalculateTravelTimes(for dayIndex: Int) {
        let slots = itinerary.days[dayIndex].slots
        for i in 0..<slots.count {
            if i < slots.count - 1 {
                let dist = haversineDistance(
                    lat1: slots[i].latitude, lon1: slots[i].longitude,
                    lat2: slots[i + 1].latitude, lon2: slots[i + 1].longitude
                )
                let travelMin = max(5, Int(dist / 5000.0 * 60.0))
                itinerary.days[dayIndex].slots[i].travelTimeToNextMin = travelMin
            } else {
                itinerary.days[dayIndex].slots[i].travelTimeToNextMin = nil
            }
        }
    }

    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    func openInAppleMaps(day: ItineraryDay) {
        let validSlots = day.slots.filter { $0.latitude != 0 || $0.longitude != 0 }
        guard !validSlots.isEmpty else { return }
        let mapItems = validSlots.map { slot -> MKMapItem in
            let coordinate = CLLocationCoordinate2D(latitude: slot.latitude, longitude: slot.longitude)
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = slot.activityName
            return item
        }
        MKMapItem.openMaps(with: mapItems, launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    func recalculateCost() {
        var activitiesTotal = 0.0
        var foodTotal = 0.0
        for day in itinerary.days {
            for slot in day.slots {
                activitiesTotal += slot.estimatedCostUsd ?? 0
            }
            for meal in day.meals {
                foodTotal += meal.estimatedCostUsd ?? 0
            }
        }
        let perDay = itinerary.days.map { day in
            let dayActivities = day.slots.reduce(0.0) { $0 + ($1.estimatedCostUsd ?? 0) }
            let dayFood = day.meals.reduce(0.0) { $0 + ($1.estimatedCostUsd ?? 0) }
            return DayCost(day: day.dayNumber, hotel: 0, hotelIsEstimated: true, food: dayFood, foodIsEstimated: true, activities: dayActivities, subtotal: dayActivities + dayFood)
        }
        estimatedCost = CostBreakdown(
            hotelTotal: 0,
            hotelIsEstimated: true,
            foodTotal: foodTotal,
            foodIsEstimated: true,
            activitiesTotal: activitiesTotal,
            total: activitiesTotal + foodTotal,
            perDay: perDay
        )
    }
}

// MARK: - Day Selector View

struct DaySelectorView: View {
    let days: [ItineraryDay]
    @Binding var selectedDay: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.spacingSM) {
                ForEach(days) { day in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDay = day.dayNumber
                        }
                    } label: {
                        Text("Day \(day.dayNumber)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedDay == day.dayNumber ? .white : DesignTokens.textSecondary)
                            .padding(.horizontal, DesignTokens.spacingMD)
                            .padding(.vertical, DesignTokens.spacingSM)
                            .background(
                                Group {
                                    if selectedDay == day.dayNumber {
                                        RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                                            .fill(DesignTokens.accentGradient)
                                    } else {
                                        RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                                            .stroke(DesignTokens.surfaceGlassBorder, lineWidth: 1)
                                            .background(
                                                RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                                                    .fill(DesignTokens.surfaceGlass)
                                            )
                                    }
                                }
                            )
                    }
                    .accessibilityLabel("Day \(day.dayNumber)")
                    .accessibilityAddTraits(selectedDay == day.dayNumber ? .isSelected : [])
                }
            }
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.vertical, DesignTokens.spacingSM)
        }
    }
}

// MARK: - Itinerary View (standalone)

struct ItineraryView: View {

    @StateObject private var viewModel: ItineraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Int = 1

    init(itinerary: ItineraryResponse) {
        _viewModel = StateObject(wrappedValue: ItineraryViewModel(itinerary: itinerary))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    DaySelectorView(days: viewModel.itinerary.days, selectedDay: $selectedDay)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            whyThisPlanCard

                            if let day = viewModel.itinerary.days.first(where: { $0.dayNumber == selectedDay }) {
                                InlineDaySectionView(day: day, viewModel: viewModel)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }

                if viewModel.isReplacing {
                    replacingOverlay
                }
            }
            .navigationTitle("\(viewModel.itinerary.destination) Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
            .sheet(isPresented: $viewModel.showDetail) {
                if let slot = viewModel.selectedSlot {
                    SlotDetailView(slot: slot)
                }
            }
            .sheet(isPresented: $viewModel.showAddActivity) {
                AddActivitySheet(dayNumber: viewModel.addActivityDayNumber) { name, desc, duration, timeSlot in
                    viewModel.addActivity(to: viewModel.addActivityDayNumber, name: name, description: desc, durationMin: duration, timeSlot: timeSlot)
                }
            }
            .sheet(isPresented: $viewModel.showReplaceSuggestions) {
                replaceSuggestionsSheet
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                viewModel.recalculateCost()
            }
        }
    }

    private var whyThisPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why This Plan", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.accentCyan)
            if let reasoning = viewModel.itinerary.reasoningText, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            Text("Optimized for minimal travel time and best experience flow")
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(DesignTokens.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Why This Plan")
    }

    @ViewBuilder
    private var replaceSuggestionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.spacingSM) {
                    if viewModel.replaceTargetSlot != nil {
                        ForEach(viewModel.replaceSuggestions) { suggestion in
                            Button {
                                viewModel.selectReplacement(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.activityName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Text(suggestion.description)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        if let cost = suggestion.estimatedCostUsd, cost > 0 {
                                            Text("~$\(Int(cost))")
                                        }
                                        Text("\(suggestion.estimatedDurationMin) min")
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
                    } else if viewModel.replaceTargetMeal != nil {
                        ForEach(viewModel.mealReplaceSuggestions) { suggestion in
                            Button {
                                viewModel.selectMealReplacement(suggestion)
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
                }
                .padding(DesignTokens.spacingMD)
            }
            .background(DesignTokens.backgroundPrimary)
            .navigationTitle("Pick a Replacement")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var replacingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(DesignTokens.accentCyan)
                Text("Finding alternatives…")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .padding(24)
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        }
    }
}

// MARK: - Slot Detail View

struct SlotDetailView: View {

    let slot: ItinerarySlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if slot.latitude != 0, slot.longitude != 0 {
                        let region = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: slot.latitude, longitude: slot.longitude),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                        Map(initialPosition: .region(region)) {
                            Marker(slot.activityName, coordinate: CLLocationCoordinate2D(
                                latitude: slot.latitude, longitude: slot.longitude
                            ))
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
                        .allowsHitTesting(false)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(slot.timeSlot)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.textSecondary)
                        Text(slot.activityName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text(slot.description)
                            .font(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    Divider().overlay(DesignTokens.surfaceGlassBorder)

                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(icon: "clock", label: "Duration", value: "\(slot.estimatedDurationMin) minutes")
                        if let cost = slot.estimatedCostUsd, cost > 0 {
                            detailRow(icon: "dollarsign.circle", label: "Estimated Cost", value: "$\(Int(cost))")
                        }
                        if let travel = slot.travelTimeToNextMin, travel > 0 {
                            detailRow(icon: "car", label: "Travel to Next", value: "\(travel) minutes")
                        }
                        if slot.latitude != 0, slot.longitude != 0 {
                            detailRow(icon: "location", label: "Coordinates", value: String(format: "%.4f, %.4f", slot.latitude, slot.longitude))
                        }
                    }

                    Spacer()
                }
                .padding(DesignTokens.spacingMD)
            }
            .background(DesignTokens.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Activity Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.accentCyan)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Add Activity Sheet

struct AddActivitySheet: View {

    let dayNumber: Int
    var destination: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    let onAdd: (String, String, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedTimeBlock: String = "Morning"
    @State private var searchResults: [PlaceRecommendation] = []
    @State private var isSearching: Bool = false

    private let timeBlocks = ["Morning", "Afternoon", "Evening"]

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
                    Text("Add Activity to Day \(dayNumber)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, DesignTokens.spacingMD)

                    // Name with autocomplete
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Activity name")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                        HStack {
                            TextField("Search places...", text: $name)
                                .font(.body)
                                .foregroundStyle(DesignTokens.textPrimary)
                            if isSearching {
                                ProgressView().controlSize(.small).tint(DesignTokens.accentCyan)
                            }
                        }
                        .padding(DesignTokens.spacingSM)
                        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                        .onChange(of: name) { _, newValue in
                            Task {
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                guard name == newValue, newValue.count >= 2 else { return }
                                await searchPlaces(query: newValue)
                            }
                        }

                        // Autocomplete results
                        if !searchResults.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(searchResults.prefix(5)) { place in
                                    Button {
                                        name = place.name
                                        description = place.formattedRestaurantPrice
                                        searchResults = []
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(place.name)
                                                    .font(.subheadline)
                                                    .foregroundStyle(DesignTokens.textPrimary)
                                                if place.rating > 0 {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                                                        Text(String(format: "%.1f", place.rating))
                                                    }
                                                    .font(.caption2)
                                                    .foregroundStyle(DesignTokens.textSecondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle")
                                                .foregroundStyle(DesignTokens.accentCyan)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, DesignTokens.spacingSM)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                        }
                    }
                    .padding(.horizontal, DesignTokens.spacingMD)

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description (optional)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                        TextField("Brief description", text: $description)
                            .font(.body)
                            .foregroundStyle(DesignTokens.textPrimary)
                            .padding(DesignTokens.spacingSM)
                            .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                    }
                    .padding(.horizontal, DesignTokens.spacingMD)

                    // Time block
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Block")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                        Picker("Time Block", selection: $selectedTimeBlock) {
                            ForEach(timeBlocks, id: \.self) { block in
                                Text(block).tag(block)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, DesignTokens.spacingMD)

                    // Add button
                    Button {
                        onAdd(name.trimmingCharacters(in: .whitespaces), description, 90, selectedTimeBlock)
                        dismiss()
                    } label: {
                        Text("Add Activity")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValid ? DesignTokens.accentGradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                    }
                    .disabled(!isValid)
                    .padding(.horizontal, DesignTokens.spacingMD)
                }
                .padding(.vertical, DesignTokens.spacingMD)
            }
            .background(DesignTokens.backgroundPrimary)
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
        }
    }

    private func searchPlaces(query: String) async {
        guard latitude != 0, longitude != 0 else { return }
        isSearching = true
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "place_type", value: "restaurant"),
        ]
        do {
            let response: PlacesResponse = try await APIClient.shared.request(
                .get, path: "/places/search", queryItems: queryItems
            )
            searchResults = response.results
        } catch {
            searchResults = []
        }
        isSearching = false
    }
}

// MARK: - Preview

#Preview {
    let sampleItinerary = ItineraryResponse(
        destination: "Tokyo",
        numDays: 2,
        vibes: ["Foodie"],
        budgetTier: "$$$",
        days: [
            ItineraryDay(
                dayNumber: 1,
                slots: [
                    ItinerarySlot(timeSlot: "Morning", activityName: "Tsukiji Outer Market", description: "Explore fresh seafood stalls", latitude: 35.6654, longitude: 139.7707, estimatedDurationMin: 120, travelTimeToNextMin: 15, estimatedCostUsd: 20),
                    ItinerarySlot(timeSlot: "Afternoon", activityName: "Senso-ji Temple", description: "Visit Tokyo's oldest temple", latitude: 35.7148, longitude: 139.7967, estimatedDurationMin: 90, travelTimeToNextMin: 20, estimatedCostUsd: 0),
                    ItinerarySlot(timeSlot: "Evening", activityName: "Shibuya Crossing", description: "Experience the world's busiest crossing", latitude: 35.6595, longitude: 139.7004, estimatedDurationMin: 60, travelTimeToNextMin: nil, estimatedCostUsd: 0)
                ],
                meals: [
                    MealSlot(mealType: "Breakfast", restaurantName: "Sushi Dai", cuisine: "Sushi", priceLevel: "$$", latitude: 35.6655, longitude: 139.7710, estimatedCostUsd: 35, isEstimated: true),
                    MealSlot(mealType: "Lunch", restaurantName: "Ichiran", cuisine: "Ramen", priceLevel: "$$", latitude: 35.66, longitude: 139.70, estimatedCostUsd: 15, isEstimated: true),
                ]
            ),
        ]
    )
    ItineraryView(itinerary: sampleItinerary)
}
