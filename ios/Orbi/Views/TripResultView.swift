import SwiftUI

// MARK: - Trip Result Tabs

/// Tabs displayed after itinerary generation.
enum TripResultTab: String, CaseIterable, Identifiable {
    case itinerary = "Itinerary"
    case recommendations = "Places"
    case cost = "Cost"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .itinerary: return "list.bullet.below.rectangle"
        case .recommendations: return "building.2"
        case .cost: return "dollarsign.circle"
        }
    }
}

// MARK: - Trip Result View

/// Combines Itinerary, Recommendations, and Cost views into a tabbed interface
/// with Save and Share actions accessible from the toolbar.
/// Validates: Requirements 1.1, 1.4, 2.3, 3.5, 9.1, 10.1
struct TripResultView: View {

    let itinerary: ItineraryResponse
    let city: CityMarker
    let hotelPriceRange: String
    let hotelVibe: String?
    let restaurantPriceRange: String
    let cuisineType: String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: TripResultTab = .itinerary
    @State private var savedTripId: String?
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var showSaveSuccess: Bool = false

    @StateObject private var itineraryVM: ItineraryViewModel
    @StateObject private var recommendationsVM: RecommendationsViewModel
    @StateObject private var costVM: CostViewModel

    init(
        itinerary: ItineraryResponse,
        city: CityMarker,
        hotelPriceRange: String,
        hotelVibe: String?,
        restaurantPriceRange: String,
        cuisineType: String?
    ) {
        self.itinerary = itinerary
        self.city = city
        self.hotelPriceRange = hotelPriceRange
        self.hotelVibe = hotelVibe
        self.restaurantPriceRange = restaurantPriceRange
        self.cuisineType = cuisineType

        _itineraryVM = StateObject(wrappedValue: ItineraryViewModel(itinerary: itinerary))
        _recommendationsVM = StateObject(wrappedValue: RecommendationsViewModel(
            latitude: city.latitude,
            longitude: city.longitude,
            hotelPriceRange: hotelPriceRange,
            hotelVibe: hotelVibe,
            restaurantPriceRange: restaurantPriceRange,
            cuisineType: cuisineType
        ))
        _costVM = StateObject(wrappedValue: CostViewModel(
            itinerary: itinerary,
            restaurantPriceRange: restaurantPriceRange
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                tabPicker

                // Tab content
                tabContent
            }
            .navigationTitle("\(itinerary.destination)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    // Share button (Req 10.1)
                    if let tripId = savedTripId {
                        ShareTripButton(tripId: tripId)
                    }
                    // Save button (Req 9.1)
                    saveButton
                }
            }
            .alert("Trip Saved!", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your trip to \(itinerary.destination) has been saved to My Trips.")
            }
            .alert("Save Error", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .onAppear {
                // Wire hotel selection to cost recalculation (Req 8.5)
                recommendationsVM.onHotelSelectionChanged = { hotel in
                    guard let hotel else { return }
                    Task {
                        // Estimate nightly rate from price level
                        let rate = estimateNightlyRate(priceLevel: hotel.priceLevel)
                        await costVM.recalculate(hotelNightlyRate: rate)
                    }
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
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
                    .foregroundStyle(selectedTab == tab ? .orange : .secondary)
                    .background(
                        selectedTab == tab
                            ? Color.orange.opacity(0.1)
                            : Color.clear
                    )
                }
                .accessibilityLabel("\(tab.rawValue) tab")
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .itinerary:
            itineraryTab
        case .recommendations:
            RecommendationsView(viewModel: recommendationsVM)
        case .cost:
            ScrollView {
                CostBreakdownView(viewModel: costVM)
            }
        }
    }

    // MARK: - Itinerary Tab (inline, not wrapped in NavigationStack)

    private var itineraryTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
            AddActivitySheet(dayNumber: itineraryVM.addActivityDayNumber) { name, desc, duration in
                itineraryVM.addActivity(to: itineraryVM.addActivityDayNumber, name: name, description: desc, durationMin: duration)
            }
        }
    }

    // MARK: - Save Button (Req 9.1)

    @ViewBuilder
    private var saveButton: some View {
        if savedTripId != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Trip saved")
        } else {
            Button {
                Task { await saveTrip() }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(isSaving)
            .accessibilityLabel("Save trip")
        }
    }

    // MARK: - Save Trip

    private func saveTrip() async {
        isSaving = true
        saveError = nil

        let request = TripSaveRequest(
            destination: itinerary.destination,
            destinationLatLng: "\(city.latitude),\(city.longitude)",
            numDays: itinerary.numDays,
            vibe: itinerary.vibe,
            preferences: nil,
            itinerary: nil,
            selectedHotelId: recommendationsVM.selectedHotel?.placeId,
            selectedRestaurants: nil,
            costBreakdown: nil
        )

        do {
            let response: TripResponse = try await APIClient.shared.request(
                .post, path: "/trips", body: request
            )
            savedTripId = response.id
            showSaveSuccess = true
        } catch let error as APIError {
            saveError = error.errorDescription
        } catch {
            saveError = "Failed to save trip. Please try again."
        }

        isSaving = false
    }

    // MARK: - Helpers

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

/// Renders a single day's itinerary section for use inside TripResultView.
/// Reuses ItineraryViewModel for state management.
struct InlineDaySectionView: View {

    let day: ItineraryDay
    @ObservedObject var viewModel: ItineraryViewModel
    @State private var mapRouteDay: ItineraryDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header with map button
            daySectionHeader

            // Slots
            ForEach(Array(day.slots.enumerated()), id: \.element.id) { index, slot in
                inlineSlotRow(slot: slot, isLast: index == day.slots.count - 1)
            }

            // Restaurant
            if let restaurant = day.restaurant {
                inlineRestaurantRow(restaurant: restaurant)
            }

            // Add activity
            Button {
                viewModel.addActivityDayNumber = day.dayNumber
                viewModel.showAddActivity = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Activity")
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .accessibilityLabel("Add activity to Day \(day.dayNumber)")
        }
        .sheet(item: $mapRouteDay) { day in
            MapRouteView(day: day)
        }
    }

    private var daySectionHeader: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(.orange)
            Text("Day \(day.dayNumber)")
                .font(.title3.weight(.bold))
            Spacer()
            Button {
                mapRouteDay = day
            } label: {
                Label("Map", systemImage: "map")
                    .font(.caption.weight(.medium))
            }
            .accessibilityLabel("Show map route for Day \(day.dayNumber)")
            Text("\(day.slots.count) activities")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func inlineSlotRow(slot: ItinerarySlot, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(timeSlotColor(slot.timeSlot))
                    .frame(width: 12, height: 12)
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(slot.timeSlot)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(timeSlotColor(slot.timeSlot))
                Text(slot.activityName)
                    .font(.body.weight(.medium))
                Text(slot.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)

                // Actions
                HStack(spacing: 16) {
                    Button {
                        Task {
                            await viewModel.replaceActivity(dayNumber: day.dayNumber, slot: slot)
                        }
                    } label: {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
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
            }
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedSlot = slot
            viewModel.showDetail = true
        }
    }

    private func inlineRestaurantRow(restaurant: ItineraryRestaurant) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("Restaurant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(restaurant.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Text(restaurant.cuisine)
                    Text(restaurant.priceLevel)
                    Label(String(format: "%.1f", restaurant.rating), systemImage: "star.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func timeSlotColor(_ timeSlot: String) -> Color {
        switch timeSlot.lowercased() {
        case "morning": return .orange
        case "afternoon": return .blue
        case "evening": return .purple
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleItinerary = ItineraryResponse(
        destination: "Tokyo",
        numDays: 2,
        vibe: "Foodie",
        days: [
            ItineraryDay(
                dayNumber: 1,
                slots: [
                    ItinerarySlot(timeSlot: "Morning", activityName: "Tsukiji Outer Market", description: "Explore fresh seafood stalls and street food", latitude: 35.6654, longitude: 139.7707, estimatedDurationMin: 120, travelTimeToNextMin: 15, estimatedCostUsd: 20),
                    ItinerarySlot(timeSlot: "Afternoon", activityName: "Senso-ji Temple", description: "Visit Tokyo's oldest temple in Asakusa", latitude: 35.7148, longitude: 139.7967, estimatedDurationMin: 90, travelTimeToNextMin: 20, estimatedCostUsd: 0),
                ],
                restaurant: ItineraryRestaurant(name: "Sushi Dai", cuisine: "Sushi", priceLevel: "$$", rating: 4.7, latitude: 35.6655, longitude: 139.7710, imageUrl: nil)
            ),
        ]
    )
    TripResultView(
        itinerary: sampleItinerary,
        city: CityMarker(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        hotelPriceRange: "$$",
        hotelVibe: nil,
        restaurantPriceRange: "$$",
        cuisineType: "Japanese"
    )
}
