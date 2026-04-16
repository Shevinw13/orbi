import SwiftUI
import UIKit

// MARK: - Trip Result Tabs (4 tabs)

/// Tabs displayed after itinerary generation.
enum TripResultTab: String, CaseIterable, Identifiable {
    case itinerary = "Itinerary"
    case stays = "Stays"
    case foodDrinks = "Food & Drinks"
    case cost = "Cost"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .itinerary: return "calendar"
        case .stays: return "building.2"
        case .foodDrinks: return "fork.knife"
        case .cost: return "dollarsign.circle"
        }
    }
}

// MARK: - Trip Result View

struct TripResultView: View {

    let itinerary: ItineraryResponse
    let city: CityMarker
    let vibes: [String]
    let budgetTier: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: TripResultTab = .itinerary
    @State private var savedTripId: String?
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var showShareSheet: Bool = false
    @State private var plannedByText: String = ""
    @State private var showShareToExplorePrompt: Bool = false
    @State private var showSharePublishView: Bool = false

    @StateObject private var itineraryVM: ItineraryViewModel
    @StateObject private var recommendationsVM: RecommendationsViewModel
    @StateObject private var costVM: CostViewModel

    init(
        itinerary: ItineraryResponse,
        city: CityMarker,
        vibes: [String],
        budgetTier: String
    ) {
        self.itinerary = itinerary
        self.city = city
        self.vibes = vibes
        self.budgetTier = budgetTier

        _itineraryVM = StateObject(wrappedValue: ItineraryViewModel(itinerary: itinerary))
        _recommendationsVM = StateObject(wrappedValue: RecommendationsViewModel(
            latitude: city.latitude,
            longitude: city.longitude,
            cityName: city.name
        ))
        _costVM = StateObject(wrappedValue: CostViewModel(
            itinerary: itinerary,
            budgetTier: budgetTier
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    tripHeader
                    tabPicker
                    tabContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(DesignTokens.accentCyan)
                    .accessibilityLabel("Share trip")
                    bookmarkButton
                }
            }
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Save Error", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheetView(
                    itinerary: itineraryVM.itinerary,
                    plannedBy: $plannedByText,
                    selectedHotel: recommendationsVM.selectedHotel
                )
            }
            .alert("Share this trip to Explore?", isPresented: $showShareToExplorePrompt) {
                Button("Share") { showSharePublishView = true }
                Button("Not now", role: .cancel) { }
            }
            .sheet(isPresented: $showSharePublishView) {
                if let tripId = savedTripId {
                    SharePublishView(tripId: tripId, tripDestination: itinerary.destination)
                }
            }
            .onAppear {
                loadPersistedBookmarkState()
                recommendationsVM.onHotelSelectionChanged = { hotel in
                    guard let hotel else { return }
                    Task {
                        let rate = estimateNightlyRate(priceLevel: hotel.priceLevel)
                        await costVM.recalculate(hotelNightlyRate: rate)
                    }
                }
                if savedTripId == nil {
                    Task { await checkIfAlreadySaved() }
                }
            }
        }
    }

    // MARK: - Trip Header

    private var tripHeader: some View {
        VStack(spacing: 4) {
            Text(itinerary.destination)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)
            HStack(spacing: 6) {
                Text("\(itinerary.numDays) days")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
                if !vibes.isEmpty {
                    Text("·")
                        .foregroundStyle(DesignTokens.textTertiary)
                    Text(vibes.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.accentCyan)
                }
            }
        }
        .padding(.vertical, DesignTokens.spacingSM)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: DesignTokens.spacingXS) {
            ForEach(TripResultTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.subheadline)
                        Text(tab.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedTab == tab ? DesignTokens.accentCyan : DesignTokens.textSecondary)
                    .background(
                        selectedTab == tab
                            ? AnyShapeStyle(DesignTokens.accentCyan.opacity(0.15))
                            : AnyShapeStyle(Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
                }
                .accessibilityLabel("\(tab.rawValue) tab")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        .padding(.horizontal, DesignTokens.spacingMD)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .itinerary:
            itineraryTab
        case .stays:
            StaysView(viewModel: recommendationsVM, budgetTier: budgetTier, numDays: itinerary.numDays, costVM: costVM)
        case .foodDrinks:
            FoodDrinksView(itineraryVM: itineraryVM, budgetTier: budgetTier, vibes: vibes)
        case .cost:
            ScrollView {
                CostBreakdownView(viewModel: costVM, itinerary: itineraryVM.itinerary)
            }
        }
    }

    // MARK: - Itinerary Tab

    private var itineraryTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                whyThisPlanCard
                ForEach(itineraryVM.itinerary.days) { day in
                    InlineDaySectionView(day: day, viewModel: itineraryVM)
                }
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $itineraryVM.showDetail) {
            if let slot = itineraryVM.selectedSlot {
                SlotDetailView(slot: slot)
            }
        }
        .sheet(isPresented: $itineraryVM.showAddActivity) {
            AddActivitySheet(dayNumber: itineraryVM.addActivityDayNumber) { name, desc, duration, timeSlot in
                itineraryVM.addActivity(to: itineraryVM.addActivityDayNumber, name: name, description: desc, durationMin: duration, timeSlot: timeSlot)
            }
        }
    }

    private var whyThisPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why This Plan", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.accentCyan)
            if let reasoning = itineraryVM.itinerary.reasoningText, !reasoning.isEmpty {
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

    // MARK: - Bookmark Button

    @ViewBuilder
    private var bookmarkButton: some View {
        Button {
            Task { await toggleBookmark() }
        } label: {
            if isSaving {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: savedTripId != nil ? "bookmark.fill" : "bookmark")
            }
        }
        .foregroundStyle(DesignTokens.accentCyan)
        .disabled(isSaving)
        .accessibilityLabel(savedTripId != nil ? "Remove bookmark" : "Bookmark trip")
    }

    private func toggleBookmark() async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let tripId = savedTripId {
            await unsaveTrip(tripId: tripId)
        } else {
            await saveTrip()
        }
    }

    private func saveTrip() async {
        isSaving = true
        saveError = nil

        // Serialize the current itinerary into [String: AnyCodableValue]
        var itineraryDict: [String: AnyCodableValue]? = nil
        if let data = try? JSONEncoder().encode(itineraryVM.itinerary),
           let jsonObj = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data) {
            itineraryDict = jsonObj
        }

        let request = TripSaveRequest(
            destination: itinerary.destination,
            destinationLatLng: "\(city.latitude),\(city.longitude)",
            numDays: itinerary.numDays,
            vibe: vibes.first,
            preferences: nil,
            itinerary: itineraryDict,
            selectedHotelId: recommendationsVM.selectedHotel?.placeId,
            selectedRestaurants: nil,
            costBreakdown: nil
        )
        do {
            let response: TripResponse = try await APIClient.shared.request(
                .post, path: "/trips", body: request
            )
            savedTripId = response.id
            persistBookmarkState(tripId: response.id)
            showShareToExplorePrompt = true
        } catch let error as APIError {
            saveError = error.errorDescription
        } catch {
            saveError = "Failed to save trip. Please try again."
        }
        isSaving = false
    }

    private func unsaveTrip(tripId: String) async {
        isSaving = true
        saveError = nil
        do {
            try await APIClient.shared.requestVoid(.delete, path: "/trips/\(tripId)")
            savedTripId = nil
            clearPersistedBookmarkState()
        } catch let error as APIError {
            saveError = error.errorDescription
        } catch {
            saveError = "Failed to remove trip. Please try again."
        }
        isSaving = false
    }

    private var bookmarkPersistenceKey: String {
        // Use a unique key per generation session to avoid false matches
        let vibesKey = vibes.sorted().joined(separator: ",")
        let daysKey = itineraryVM.itinerary.days.flatMap { $0.slots.map(\.activityName) }.prefix(3).joined(separator: "|")
        return "bookmark_\(itinerary.destination)_\(itinerary.numDays)_\(vibesKey)_\(daysKey)"
    }

    private func persistBookmarkState(tripId: String) {
        UserDefaults.standard.set(tripId, forKey: bookmarkPersistenceKey)
    }

    private func clearPersistedBookmarkState() {
        UserDefaults.standard.removeObject(forKey: bookmarkPersistenceKey)
    }

    private func loadPersistedBookmarkState() {
        if let persisted = UserDefaults.standard.string(forKey: bookmarkPersistenceKey) {
            savedTripId = persisted
        }
    }

    private func checkIfAlreadySaved() async {
        // Only restore bookmark if we have a persisted key for this exact itinerary
        if let persisted = UserDefaults.standard.string(forKey: bookmarkPersistenceKey) {
            savedTripId = persisted
        }
    }

    private func estimateNightlyRate(priceLevel: String) -> Double {
        switch priceLevel {
        case "$": return 80
        case "$$": return 150
        case "$$$": return 250
        default: return 100
        }
    }
}

// MARK: - Inline Day Section View

struct InlineDaySectionView: View {

    let day: ItineraryDay
    @ObservedObject var viewModel: ItineraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            daySectionHeader

            // Time blocks with merged activities and meals
            let items = day.timeBlockItems
            let blocks = ["Morning", "Afternoon", "Evening"]
            ForEach(blocks, id: \.self) { block in
                let blockItems = items.filter { $0.timeBlock == block }
                if !blockItems.isEmpty {
                    timeBlockHeader(block)
                    ForEach(Array(blockItems.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .activity(let slot):
                            inlineSlotCard(slot: slot, isLast: index == blockItems.count - 1)
                        case .meal(let meal):
                            inlineMealCard(meal: meal)
                        }
                    }
                }
            }

            // Add actions
            addItemMenu(dayNumber: day.dayNumber)
        }
    }

    private var daySectionHeader: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(DesignTokens.accentCyan)
            Text("Day \(day.dayNumber)")
                .font(.title3.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            Button {
                viewModel.openInAppleMaps(day: day)
            } label: {
                Label("Apple Maps", systemImage: "map.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.accentCyan)
            }
            .disabled(day.slots.isEmpty)
            .opacity(day.slots.isEmpty ? 0.4 : 1.0)
            .accessibilityLabel("Open Day \(day.dayNumber) in Apple Maps")
            Text("\(day.slots.count + day.meals.count) items")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .background(DesignTokens.backgroundSecondary)
    }

    private func timeBlockHeader(_ block: String) -> some View {
        Text(block)
            .font(.caption.weight(.bold))
            .foregroundStyle(timeSlotColor(block))
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.top, DesignTokens.spacingSM)
            .padding(.bottom, DesignTokens.spacingXS)
    }

    private func inlineSlotCard(slot: ItinerarySlot, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(timeSlotColor(slot.timeSlot))
                    .frame(width: 12, height: 12)
                if !isLast {
                    Rectangle()
                        .fill(DesignTokens.surfaceGlassBorder)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text(slot.activityName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                if let tag = slot.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.accentCyan.opacity(0.2)))
                }
                Text(slot.description)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label("\(slot.estimatedDurationMin) min", systemImage: "clock")
                    if let cost = slot.estimatedCostUsd, cost > 0 {
                        Label("$\(Int(cost))", systemImage: "dollarsign.circle")
                    }
                    if let travel = slot.travelTimeToNextMin, travel > 0 {
                        Label("\(travel) min travel", systemImage: "car")
                    }
                }
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)

                HStack(spacing: 16) {
                    Button {
                        Task {
                            await viewModel.replaceActivity(dayNumber: day.dayNumber, slot: slot)
                        }
                    } label: {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.accentCyan)
                    }
                    .disabled(viewModel.isReplacing)

                    Button(role: .destructive) {
                        viewModel.removeActivity(from: day.dayNumber, slot: slot)
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption2)
                    }
                }
                .padding(.top, 4)

                ExternalLinkButton(placeName: slot.activityName, city: viewModel.itinerary.destination)
            }
            .padding(DesignTokens.spacingSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingXS)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedSlot = slot
            viewModel.showDetail = true
        }
    }

    private func inlineMealCard(meal: MealSlot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .foregroundStyle(DesignTokens.accentCyan)
                .font(.title3)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meal.mealType)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.accentCyan))
                    Text(meal.restaurantName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                HStack(spacing: 8) {
                    Text(meal.cuisine)
                    Text(meal.priceLevel)
                    if let cost = meal.estimatedCostUsd, cost > 0 {
                        Text("~$\(Int(cost))/person")
                    }
                }
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)

                if meal.isEstimated {
                    Text("Est. per person")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                }

                HStack(spacing: 16) {
                    Button {
                        Task {
                            await viewModel.replaceMeal(dayNumber: day.dayNumber, meal: meal)
                        }
                    } label: {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.accentCyan)
                    }
                    .disabled(viewModel.isReplacing)

                    Button(role: .destructive) {
                        viewModel.removeMeal(from: day.dayNumber, meal: meal)
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption2)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingXS)
    }

    private func addItemMenu(dayNumber: Int) -> some View {
        Menu {
            Button { viewModel.addMeal(to: dayNumber, mealType: "Breakfast") } label: {
                Label("Add Breakfast", systemImage: "sunrise")
            }
            Button { viewModel.addMeal(to: dayNumber, mealType: "Lunch") } label: {
                Label("Add Lunch", systemImage: "sun.max")
            }
            Button { viewModel.addMeal(to: dayNumber, mealType: "Dinner") } label: {
                Label("Add Dinner", systemImage: "moon")
            }
            Divider()
            Button {
                viewModel.addActivityDayNumber = dayNumber
                viewModel.showAddActivity = true
            } label: {
                Label("Add Activity", systemImage: "plus.circle")
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add")
            }
            .font(.subheadline)
            .foregroundStyle(DesignTokens.accentCyan)
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.vertical, 10)
        }
        .accessibilityLabel("Add item to Day \(dayNumber)")
    }

    private func timeSlotColor(_ timeSlot: String) -> Color {
        switch timeSlot.lowercased() {
        case "morning": return DesignTokens.accentCyan
        case "afternoon": return DesignTokens.accentBlue
        case "evening": return .purple
        default: return .gray
        }
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                ],
                meals: [
                    MealSlot(mealType: "Breakfast", restaurantName: "Sushi Dai", cuisine: "Sushi", priceLevel: "$$", latitude: 35.6655, longitude: 139.7710, estimatedCostUsd: 35, isEstimated: true),
                    MealSlot(mealType: "Lunch", restaurantName: "Ichiran Ramen", cuisine: "Ramen", priceLevel: "$$", latitude: 35.66, longitude: 139.70, estimatedCostUsd: 15, isEstimated: true),
                    MealSlot(mealType: "Dinner", restaurantName: "Gonpachi", cuisine: "Japanese", priceLevel: "$$$", latitude: 35.656, longitude: 139.726, estimatedCostUsd: 50, isEstimated: true),
                ]
            ),
        ]
    )
    TripResultView(
        itinerary: sampleItinerary,
        city: CityMarker(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        vibes: ["Foodie"],
        budgetTier: "$$$"
    )
}
