import SwiftUI

// MARK: - Saved Trips ViewModel

@MainActor
final class SavedTripsViewModel: ObservableObject {

    @Published var trips: [TripListItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var tripToDelete: TripListItem?
    @Published var showDeleteConfirmation: Bool = false
    @Published var loadedTrip: TripResponse?
    @Published var isLoadingTrip: Bool = false
    @Published var tripLoadError: String?
    @Published var tripLoadRetryId: String?

    func loadTrips() async {
        isLoading = true
        errorMessage = nil
        do {
            let items: [TripListItem] = try await APIClient.shared.request(.get, path: "/trips")
            trips = items
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load trips."
        }
        isLoading = false
    }

    func loadTrip(id: String) async {
        isLoadingTrip = true
        errorMessage = nil
        tripLoadError = nil
        tripLoadRetryId = id
        do {
            let trip: TripResponse = try await APIClient.shared.request(.get, path: "/trips/\(id)")
            loadedTrip = trip
        } catch let error as APIError {
            tripLoadError = error.errorDescription
        } catch {
            tripLoadError = "Failed to load trip."
        }
        isLoadingTrip = false
    }

    func confirmDelete(_ trip: TripListItem) {
        tripToDelete = trip
        showDeleteConfirmation = true
    }

    func deleteTrip() async {
        guard let trip = tripToDelete else { return }
        do {
            try await APIClient.shared.requestVoid(.delete, path: "/trips/\(trip.id)")
            trips.removeAll { $0.id == trip.id }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to delete trip."
        }
        tripToDelete = nil
    }
}

// MARK: - Saved Trips View

struct SavedTripsView: View {

    @StateObject private var viewModel = SavedTripsViewModel()
    @Environment(\.dismiss) private var dismiss
    var onPlanTrip: (() -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: DesignTokens.spacingMD),
        GridItem(.flexible(), spacing: DesignTokens.spacingMD)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.trips.isEmpty {
                        ProgressView("Loading trips…")
                            .tint(DesignTokens.accentCyan)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage, viewModel.trips.isEmpty {
                        VStack(spacing: 12) {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red.opacity(0.9))
                            Button("Retry") { Task { await viewModel.loadTrips() } }.foregroundStyle(DesignTokens.accentCyan)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.trips.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "suitcase").font(.system(size: 48)).foregroundStyle(DesignTokens.textSecondary)
                            Text("No trips yet").font(.headline).foregroundStyle(DesignTokens.textPrimary)
                            Button {
                                dismiss()
                                onPlanTrip?()
                            } label: {
                                Text("Plan your first trip").font(.headline).foregroundStyle(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 12)
                                    .background(DesignTokens.accentGradient).clipShape(Capsule())
                            }
                            Text("Try a weekend in Atlanta").font(.subheadline).foregroundStyle(DesignTokens.textTertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        tripsGrid
                    }
                }
            }
            .navigationTitle("My Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(DesignTokens.textPrimary)
                }
            }
            .task { await viewModel.loadTrips() }
            .alert("Delete Trip?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { viewModel.tripToDelete = nil }
                Button("Delete", role: .destructive) { Task { await viewModel.deleteTrip() } }
            } message: {
                if let trip = viewModel.tripToDelete {
                    Text("Are you sure you want to delete your \(trip.destination) trip?")
                }
            }
            .sheet(item: $viewModel.loadedTrip) { trip in
                SavedTripDetailView(trip: trip)
            }
            .alert("Load Error", isPresented: .init(
                get: { viewModel.tripLoadError != nil },
                set: { if !$0 { viewModel.tripLoadError = nil } }
            )) {
                Button("Retry") {
                    if let retryId = viewModel.tripLoadRetryId { Task { await viewModel.loadTrip(id: retryId) } }
                }
                Button("OK", role: .cancel) { viewModel.tripLoadError = nil }
            } message: {
                Text(viewModel.tripLoadError ?? "")
            }
        }
    }

    private var tripsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignTokens.spacingMD) {
                ForEach(viewModel.trips) { trip in
                    tripCard(trip)
                        .contextMenu {
                            Button(role: .destructive) { viewModel.confirmDelete(trip) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
            .padding(DesignTokens.spacingMD)
        }
        .refreshable { await viewModel.loadTrips() }
        .overlay {
            if viewModel.isLoadingTrip {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Loading trip…").tint(DesignTokens.accentCyan).foregroundStyle(DesignTokens.textPrimary)
                        .padding(24).glassmorphic(cornerRadius: DesignTokens.radiusMD)
                }
            }
        }
    }

    private func tripCard(_ trip: TripListItem) -> some View {
        Button { Task { await viewModel.loadTrip(id: trip.id) } } label: {
            VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
                RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                    .fill(LinearGradient(colors: [DesignTokens.accentCyan.opacity(0.3), DesignTokens.accentBlue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 100)
                    .overlay(Image(systemName: "airplane").font(.title).foregroundStyle(DesignTokens.textSecondary))

                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.destination).font(.subheadline.weight(.bold)).foregroundStyle(DesignTokens.textPrimary).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.caption2)
                        Text("\(trip.numDays) days").font(.caption)
                    }
                    .foregroundStyle(DesignTokens.textSecondary)
                    if let vibe = trip.vibe {
                        Text(vibe).font(.caption2).foregroundStyle(DesignTokens.accentCyan)
                    }
                    Text(formattedDate(trip.createdAt)).font(.caption2).foregroundStyle(DesignTokens.textTertiary)
                }
                .padding(.horizontal, DesignTokens.spacingSM)
                .padding(.bottom, DesignTokens.spacingSM)
            }
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.destination), \(trip.numDays) days")
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return isoString }
            return formatDisplay(date)
        }
        return formatDisplay(date)
    }

    private func formatDisplay(_ date: Date) -> String {
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }
}

// MARK: - Saved Trip Detail View

struct SavedTripDetailView: View {

    let trip: TripResponse
    @Environment(\.dismiss) private var dismiss
    @State private var showSharePublish: Bool = false

    private var decodedItinerary: ItineraryResponse? {
        guard let dict = trip.itinerary else { return nil }
        return Self.decode(ItineraryResponse.self, from: dict)
    }

    private var decodedCostBreakdown: CostBreakdown? {
        guard let dict = trip.costBreakdown else { return nil }
        return Self.decode(CostBreakdown.self, from: dict)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tripHeader
                    Divider().overlay(DesignTokens.surfaceGlassBorder).padding(.horizontal, DesignTokens.spacingMD)
                    if let itinerary = decodedItinerary {
                        itinerarySection(itinerary)
                    } else {
                        noItineraryFallback
                    }
                    if let costBreakdown = decodedCostBreakdown {
                        costBreakdownSection(costBreakdown)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(DesignTokens.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(DesignTokens.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSharePublish = true
                    } label: {
                        Label("Share to Explore", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(DesignTokens.accentCyan)
                }
            }
            .sheet(isPresented: $showSharePublish) {
                SharePublishView(tripId: trip.id, tripDestination: trip.destination)
            }
        }
    }

    private var tripHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.destination).font(.title.weight(.bold)).foregroundStyle(DesignTokens.textPrimary)
            HStack(spacing: 12) {
                Label("\(trip.numDays) days", systemImage: "calendar")
                if let vibe = trip.vibe {
                    Label(vibe, systemImage: vibeIcon(vibe))
                }
            }
            .font(.subheadline)
            .foregroundStyle(DesignTokens.textSecondary)
            if let creator = trip.originalCreatorUsername, !creator.isEmpty {
                Label("Originally by \(creator)", systemImage: "person.circle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.accentCyan)
            }
        }
        .padding(DesignTokens.spacingMD)
    }

    @ViewBuilder
    private func itinerarySection(_ itinerary: ItineraryResponse) -> some View {
        if let reasoning = itinerary.reasoningText, !reasoning.isEmpty {
            whyThisPlanCard(reasoning: reasoning)
        }
        ForEach(itinerary.days) { day in
            savedDaySection(day: day)
        }
    }

    private func whyThisPlanCard(reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Why This Plan", systemImage: "lightbulb.fill").font(.subheadline.weight(.semibold)).foregroundStyle(DesignTokens.accentCyan)
            Text(reasoning).font(.caption).foregroundStyle(DesignTokens.textPrimary)
            Text("Optimized for minimal travel time and best experience flow").font(.caption2).foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(DesignTokens.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
    }

    private func savedDaySection(day: ItineraryDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "calendar").foregroundStyle(DesignTokens.accentCyan)
                Text("Day \(day.dayNumber)").font(.title3.weight(.bold)).foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text("\(day.slots.count + day.meals.count) items").font(.caption).foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.vertical, DesignTokens.spacingSM)
            .background(DesignTokens.backgroundSecondary)

            TimelineBarView(day: day) { _ in }

            ForEach(Array(day.slots.enumerated()), id: \.element.id) { index, slot in
                savedSlotCard(slot: slot, isLast: index == day.slots.count - 1)
            }

            // Meals
            ForEach(day.meals) { meal in
                savedMealRow(meal: meal)
            }
        }
    }

    private func savedSlotCard(slot: ItinerarySlot, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(timeSlotColor(slot.timeSlot)).frame(width: 12, height: 12)
                if !isLast {
                    Rectangle().fill(DesignTokens.surfaceGlassBorder).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text(slot.timeSlot).font(.caption.weight(.semibold)).foregroundStyle(timeSlotColor(slot.timeSlot))
                Text(slot.activityName).font(.body.weight(.medium)).foregroundStyle(DesignTokens.textPrimary)
                if let tag = slot.tag, !tag.isEmpty {
                    Text(tag).font(.caption2).foregroundStyle(DesignTokens.accentCyan)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(DesignTokens.accentCyan.opacity(0.2)))
                }
                Text(slot.description).font(.caption).foregroundStyle(DesignTokens.textSecondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(slot.estimatedDurationMin) min", systemImage: "clock")
                    if let cost = slot.estimatedCostUsd, cost > 0 { Label("$\(Int(cost))", systemImage: "dollarsign.circle") }
                    if let travel = slot.travelTimeToNextMin, travel > 0 { Label("\(travel) min travel", systemImage: "car") }
                }
                .font(.caption2).foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(DesignTokens.spacingSM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingXS)
    }

    private func savedMealRow(meal: MealSlot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill").foregroundStyle(DesignTokens.accentCyan).font(.title3).frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(meal.mealType).font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(DesignTokens.accentCyan))
                    Text(meal.restaurantName).font(.body.weight(.medium)).foregroundStyle(DesignTokens.textPrimary)
                }
                HStack(spacing: 8) {
                    Text(meal.cuisine)
                    Text(meal.priceLevel)
                    if let cost = meal.estimatedCostUsd, cost > 0 { Text("~$\(Int(cost))") }
                }
                .font(.caption2).foregroundStyle(DesignTokens.textSecondary)
                if meal.isEstimated {
                    Text("Estimated").font(.caption2).foregroundStyle(DesignTokens.textTertiary)
                }
            }
            .padding(.vertical, 8)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacingMD)
    }

    private var noItineraryFallback: some View {
        Text("No itinerary data available.")
            .font(.subheadline).foregroundStyle(DesignTokens.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DesignTokens.spacingLG).padding(.horizontal, DesignTokens.spacingMD)
    }

    private func costBreakdownSection(_ cost: CostBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(DesignTokens.surfaceGlassBorder).padding(.horizontal, DesignTokens.spacingMD)
            Text("Cost Breakdown").font(.title3.weight(.bold)).foregroundStyle(DesignTokens.textPrimary).padding(.horizontal, DesignTokens.spacingMD)
            VStack(spacing: 4) {
                Text("Estimated total cost").font(.caption).foregroundStyle(DesignTokens.textSecondary)
                Text("$\(Int(cost.total))").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)

            HStack(spacing: 0) {
                costCategoryPill(icon: "building.2", label: "Hotels", amount: cost.hotelTotal, isEstimated: cost.hotelIsEstimated ?? true)
                Divider().frame(height: 40)
                costCategoryPill(icon: "fork.knife", label: "Food & Drinks", amount: cost.foodTotal, isEstimated: cost.foodIsEstimated ?? true)
                Divider().frame(height: 40)
                costCategoryPill(icon: "figure.walk", label: "Activities", amount: cost.activitiesTotal, isEstimated: false)
            }
            .padding(12).glassmorphic(cornerRadius: DesignTokens.radiusMD).padding(.horizontal, DesignTokens.spacingMD)

            ForEach(cost.perDay) { day in
                HStack {
                    Text("Day \(day.day)").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    Text("$\(Int(day.subtotal))").font(.subheadline.weight(.semibold)).foregroundStyle(DesignTokens.textPrimary)
                }
                .padding(.vertical, 6).padding(.horizontal, DesignTokens.spacingMD)
            }
        }
        .padding(.top, DesignTokens.spacingSM)
    }

    private func costCategoryPill(icon: String, label: String, amount: Double, isEstimated: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(.orange)
            Text(label).font(.caption2).foregroundStyle(DesignTokens.textSecondary)
            Text("$\(Int(amount))").font(.subheadline.weight(.semibold)).foregroundStyle(DesignTokens.textPrimary)
            if isEstimated {
                Text("Estimated").font(.system(size: 9)).foregroundStyle(DesignTokens.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func vibeIcon(_ vibe: String) -> String {
        switch vibe.lowercased() {
        case "foodie": return "fork.knife"
        case "adventure": return "figure.hiking"
        case "relaxed": return "leaf.fill"
        case "nightlife": return "moon.stars.fill"
        default: return "sparkles"
        }
    }

    private func timeSlotColor(_ timeSlot: String) -> Color {
        switch timeSlot.lowercased() {
        case "morning": return DesignTokens.accentCyan
        case "afternoon": return DesignTokens.accentBlue
        case "evening": return .purple
        default: return .gray
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from dict: [String: AnyCodableValue]) -> T? {
        guard let data = try? JSONEncoder().encode(dict) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

#Preview { SavedTripsView() }
