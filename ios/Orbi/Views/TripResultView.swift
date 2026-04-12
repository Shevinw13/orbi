import SwiftUI
import UIKit

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
    @State private var showShareSheet: Bool = false
    @State private var plannedByText: String = ""

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
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    tripHeader

                    // Tab picker
                    tabPicker

                    // Tab content
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
                    // Share button (Req 14.5, 14.6)
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .foregroundStyle(DesignTokens.accentCyan)
                    .accessibilityLabel("Share trip")
                    // Bookmark toggle (Req 10.1, 10.2, 10.3)
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
                    plannedBy: $plannedByText
                )
            }
            .onAppear {
                // Check if trip is already saved (Req 10.4, 10.5)
                loadPersistedBookmarkState()

                // Wire hotel selection to cost recalculation (Req 8.5)
                recommendationsVM.onHotelSelectionChanged = { hotel in
                    guard let hotel else { return }
                    Task {
                        let rate = estimateNightlyRate(priceLevel: hotel.priceLevel)
                        await costVM.recalculate(hotelNightlyRate: rate)
                    }
                }

                // Check if trip is already saved on the server (Req 10.5)
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
            Text("\(itinerary.numDays) days · \(itinerary.vibe)")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
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
                // "Why This Plan" reasoning card (Req 9.1, 9.2)
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
            AddActivitySheet(dayNumber: itineraryVM.addActivityDayNumber) { name, desc, duration in
                itineraryVM.addActivity(to: itineraryVM.addActivityDayNumber, name: name, description: desc, durationMin: duration)
            }
        }
    }

    // MARK: - Why This Plan Card (Req 9.1, 9.2)

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

    // MARK: - Bookmark Button (Req 10.1, 10.2, 10.3)

    @ViewBuilder
    private var bookmarkButton: some View {
        Button {
            Task { await toggleBookmark() }
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: savedTripId != nil ? "bookmark.fill" : "bookmark")
            }
        }
        .foregroundStyle(DesignTokens.accentCyan)
        .disabled(isSaving)
        .accessibilityLabel(savedTripId != nil ? "Remove bookmark" : "Bookmark trip")
    }

    // MARK: - Bookmark Toggle (Req 10.2, 10.3)

    private func toggleBookmark() async {
        // Haptic feedback on bookmark tap (Req 16.2)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let tripId = savedTripId {
            await unsaveTrip(tripId: tripId)
        } else {
            await saveTrip()
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
            persistBookmarkState(tripId: response.id)
        } catch let error as APIError {
            saveError = error.errorDescription
        } catch {
            saveError = "Failed to save trip. Please try again."
        }

        isSaving = false
    }

    // MARK: - Unsave Trip (Req 10.3)

    private func unsaveTrip(tripId: String) async {
        isSaving = true
        saveError = nil

        do {
            try await APIClient.shared.requestVoid(
                .delete, path: "/trips/\(tripId)"
            )
            savedTripId = nil
            clearPersistedBookmarkState()
        } catch let error as APIError {
            saveError = error.errorDescription
        } catch {
            saveError = "Failed to remove trip. Please try again."
        }

        isSaving = false
    }

    // MARK: - Bookmark Persistence (Req 10.4)

    /// Key used to persist the saved trip ID in UserDefaults, scoped to this trip's identity.
    private var bookmarkPersistenceKey: String {
        "bookmark_\(itinerary.destination)_\(itinerary.numDays)_\(itinerary.vibe)"
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

    // MARK: - Check If Already Saved (Req 10.5)

    private func checkIfAlreadySaved() async {
        do {
            let trips: [TripListItem] = try await APIClient.shared.request(
                .get, path: "/trips"
            )
            if let match = trips.first(where: {
                $0.destination == itinerary.destination
                && $0.numDays == itinerary.numDays
                && $0.vibe == itinerary.vibe
            }) {
                savedTripId = match.id
                persistBookmarkState(tripId: match.id)
            }
        } catch {
            // Silently fail — bookmark will just show unfilled
        }
    }

    // MARK: - Helpers

    private func estimateNightlyRate(priceLevel: String) -> Double {
        switch priceLevel {
        case "$": return 80
        case "$": return 150
        case "$$": return 250
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
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header with map button
            daySectionHeader

            // Timeline bar (Req 8.1, 8.2, 8.3, 8.4)
            TimelineBarView(day: day) { _ in }

            // Slots
            ForEach(Array(day.slots.enumerated()), id: \.element.id) { index, slot in
                inlineSlotCard(slot: slot, isLast: index == day.slots.count - 1)
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
                .foregroundStyle(DesignTokens.accentCyan)
                .padding(.horizontal, DesignTokens.spacingMD)
                .padding(.vertical, 10)
            }
            .accessibilityLabel("Add activity to Day \(day.dayNumber)")
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
            // Open in Apple Maps button (Req 8.1, 8.2)
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
            Text("\(day.slots.count) activities")
                .font(.caption)
                .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .background(DesignTokens.backgroundSecondary)
    }

    private func inlineSlotCard(slot: ItinerarySlot, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
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

            // Activity card content
            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text(slot.timeSlot)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(timeSlotColor(slot.timeSlot))
                Text(slot.activityName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                if let tag = slot.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.accentCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(DesignTokens.accentCyan.opacity(0.2))
                        )
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

                // Actions
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

    private func inlineRestaurantRow(restaurant: ItineraryRestaurant) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .foregroundStyle(DesignTokens.accentCyan)
                .font(.title3)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("Restaurant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accentCyan)
                Text(restaurant.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                HStack(spacing: 8) {
                    Text(restaurant.cuisine)
                    Text(restaurant.priceLevel)
                    Label(String(format: "%.1f", restaurant.rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacingMD)
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

/// SwiftUI wrapper for UIActivityViewController to present the system share sheet.
/// Validates: Requirement 14.6
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
        vibe: "Foodie",
        days: [
            ItineraryDay(
                dayNumber: 1,
                slots: [
                    ItinerarySlot(timeSlot: "Morning", activityName: "Tsukiji Outer Market", description: "Explore fresh seafood stalls and street food", latitude: 35.6654, longitude: 139.7707, estimatedDurationMin: 120, travelTimeToNextMin: 15, estimatedCostUsd: 20),
                    ItinerarySlot(timeSlot: "Afternoon", activityName: "Senso-ji Temple", description: "Visit Tokyo's oldest temple in Asakusa", latitude: 35.7148, longitude: 139.7967, estimatedDurationMin: 90, travelTimeToNextMin: 20, estimatedCostUsd: 0),
                ],
                restaurant: ItineraryRestaurant(name: "Sushi Dai", cuisine: "Sushi", priceLevel: "$", rating: 4.7, latitude: 35.6655, longitude: 139.7710, imageUrl: nil)
            ),
        ]
    )
    TripResultView(
        itinerary: sampleItinerary,
        city: CityMarker(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        hotelPriceRange: "$",
        hotelVibe: nil,
        restaurantPriceRange: "$",
        cuisineType: "Japanese"
    )
}
