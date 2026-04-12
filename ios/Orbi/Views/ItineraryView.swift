import SwiftUI
import UIKit
import MapKit

// MARK: - Itinerary ViewModel

/// Manages itinerary state, drag-and-drop reordering, and item CRUD operations.
/// Validates: Requirements 5.1, 5.3, 5.4, 5.5, 5.6, 5.7, 8.5, 15.4
@MainActor
final class ItineraryViewModel: ObservableObject {

    @Published var itinerary: ItineraryResponse
    @Published var selectedSlot: ItinerarySlot?
    @Published var showDetail: Bool = false
    @Published var showAddActivity: Bool = false
    @Published var addActivityDayNumber: Int = 1
    @Published var isReplacing: Bool = false
    @Published var errorMessage: String?
    @Published var estimatedCost: CostBreakdown?

    /// Tracks the slot currently being dragged for reorder.
    @Published var draggingSlot: ItinerarySlot?
    @Published var draggingFromDay: Int?

    /// Guards against double-firing haptic feedback (Req 16.4)
    private var didFireReplaceHaptic: Bool = false

    init(itinerary: ItineraryResponse) {
        self.itinerary = itinerary
        // Auto-optimize days with ≥3 activities on load (Req 7.1)
        autoOptimizeAllDays()
    }

    // MARK: - Auto-Optimization (Req 7.1)

    /// Automatically optimizes all days with ≥3 slots using nearest-neighbor.
    private func autoOptimizeAllDays() {
        for day in itinerary.days where day.slots.count >= 3 {
            optimizeDay(day.dayNumber)
        }
    }

    // MARK: - Reorder within day (Req 5.3)

    func moveSlot(in dayNumber: Int, from source: IndexSet, to destination: Int) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        itinerary.days[dayIndex].slots.move(fromOffsets: source, toOffset: destination)
        recalculateCost()
    }

    // MARK: - Cross-day move (Req 5.4)

    func moveSlotToDay(_ slot: ItinerarySlot, fromDay: Int, toDay: Int) {
        guard fromDay != toDay else { return }
        guard let fromIndex = itinerary.days.firstIndex(where: { $0.dayNumber == fromDay }),
              let toIndex = itinerary.days.firstIndex(where: { $0.dayNumber == toDay }) else { return }
        guard let slotIndex = itinerary.days[fromIndex].slots.firstIndex(where: { $0 == slot }) else { return }

        let movedSlot = itinerary.days[fromIndex].slots.remove(at: slotIndex)
        itinerary.days[toIndex].slots.append(movedSlot)
        recalculateCost()
    }

    // MARK: - Replace activity (Req 5.5)

    func replaceActivity(dayNumber: Int, slot: ItinerarySlot) async {
        isReplacing = true
        errorMessage = nil
        didFireReplaceHaptic = false

        let allActivities = itinerary.days.flatMap { $0.slots.map(\.activityName) }

        // Build adjacent activity coordinates (Req 11.1–11.4)
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
            if !coords.isEmpty {
                adjacentCoords = coords
            }
        }

        let request = ReplaceActivityRequest(
            destination: itinerary.destination,
            dayNumber: dayNumber,
            timeSlot: slot.timeSlot,
            currentActivityName: slot.activityName,
            existingActivities: allActivities,
            vibe: itinerary.vibe,
            adjacentActivityCoords: adjacentCoords
        )

        do {
            let newSlot: ItinerarySlot = try await APIClient.shared.request(
                .post, path: "/trips/replace-item", body: request
            )
            if let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }),
               let slotIndex = itinerary.days[dayIndex].slots.firstIndex(where: { $0 == slot }) {
                itinerary.days[dayIndex].slots[slotIndex] = newSlot
            }
            recalculateCost()
            // Haptic feedback on successful activity replacement (Req 16.3)
            if !didFireReplaceHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                didFireReplaceHaptic = true
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to replace activity. Please try again."
        }

        isReplacing = false
    }

    // MARK: - Add custom activity (Req 5.6)

    func addActivity(to dayNumber: Int, name: String, description: String, durationMin: Int) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }

        let newSlot = ItinerarySlot(
            timeSlot: "Custom",
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

    // MARK: - Remove activity (Req 5.7)

    func removeActivity(from dayNumber: Int, slot: ItinerarySlot) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        itinerary.days[dayIndex].slots.removeAll { $0 == slot }
        recalculateCost()
    }

    // MARK: - Optimize Day (Req 7.1, 7.2, 7.3, 7.4, 7.5)

    func optimizeDay(_ dayNumber: Int) {
        guard let dayIndex = itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }) else { return }
        var slots = itinerary.days[dayIndex].slots
        guard slots.count >= 3 else { return }

        // Nearest-neighbor algorithm on haversine distance
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

        // Recalculate travel times between consecutive activities
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
                // Rough estimate: walking ~5 km/h
                let travelMin = max(5, Int(dist / 5000.0 * 60.0))
                itinerary.days[dayIndex].slots[i].travelTimeToNextMin = travelMin
            } else {
                itinerary.days[dayIndex].slots[i].travelTimeToNextMin = nil
            }
        }
    }

    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    // MARK: - Open in Apple Maps (Req 8.1, 8.2)

    /// Opens Apple Maps with walking directions through all activity waypoints for the given day.
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

        let launchOptions: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ]
        MKMapItem.openMaps(with: mapItems, launchOptions: launchOptions)
    }

    // MARK: - Cost recalculation (Req 8.5)

    func recalculateCost() {
        var activitiesTotal = 0.0
        for day in itinerary.days {
            for slot in day.slots {
                activitiesTotal += slot.estimatedCostUsd ?? 0
            }
        }
        let perDay = itinerary.days.map { day in
            let dayActivities = day.slots.reduce(0.0) { $0 + ($1.estimatedCostUsd ?? 0) }
            return DayCost(day: day.dayNumber, hotel: 0, food: 0, activities: dayActivities, subtotal: dayActivities)
        }
        estimatedCost = CostBreakdown(
            hotelTotal: 0,
            foodTotal: 0,
            activitiesTotal: activitiesTotal,
            total: activitiesTotal,
            perDay: perDay
        )
    }
}



// MARK: - Day Selector View

/// Horizontal scrollable row of pill buttons for day navigation.
/// Validates: Requirements 8.2, 8.3
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


// MARK: - Itinerary View (Req 5.1, 15.4)

/// Vertical timeline grouped by day with interactive itinerary items.
/// Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 8.5, 15.4
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
                    // Day selector
                    DaySelectorView(days: viewModel.itinerary.days, selectedDay: $selectedDay)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // "Why This Plan" reasoning card (Req 9.1, 9.2)
                            whyThisPlanCard

                            if let day = viewModel.itinerary.days.first(where: { $0.dayNumber == selectedDay }) {
                                daySectionView(day: day)
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
                AddActivitySheet(dayNumber: viewModel.addActivityDayNumber) { name, desc, duration in
                    viewModel.addActivity(to: viewModel.addActivityDayNumber, name: name, description: desc, durationMin: duration)
                }
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


    // MARK: - Why This Plan Card (Req 9.1, 9.2)

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


    // MARK: - Day Section

    private func daySectionView(day: ItineraryDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            daySectionHeader(day: day)
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleCrossDayDrop(providers: providers, targetDay: day.dayNumber)
                }

            // Timeline bar (Req 8.1, 8.2, 8.3, 8.4)
            TimelineBarView(day: day) { _ in
                // Scroll handled by parent ScrollView
            }

            ForEach(Array(day.slots.enumerated()), id: \.element.id) { index, slot in
                slotRow(slot: slot, dayNumber: day.dayNumber, isLast: index == day.slots.count - 1)
            }
            .onMove { source, destination in
                viewModel.moveSlot(in: day.dayNumber, from: source, to: destination)
            }

            if let restaurant = day.restaurant {
                restaurantRow(restaurant: restaurant)
            }

            addActivityButton(dayNumber: day.dayNumber)
        }
    }

    private func daySectionHeader(day: ItineraryDay) -> some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(day.dayNumber), \(day.slots.count) activities")
    }

    // MARK: - Slot Row

    private func slotRow(slot: ItinerarySlot, dayNumber: Int, isLast: Bool) -> some View {
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

            VStack(alignment: .leading, spacing: 4) {
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

                slotActions(slot: slot, dayNumber: dayNumber)

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
        .scaleEffect(viewModel.draggingSlot == slot ? 1.05 : 1.0)
        .shadow(color: viewModel.draggingSlot == slot ? DesignTokens.accentCyan.opacity(0.3) : .clear, radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.2), value: viewModel.draggingSlot == slot)
        .overlay(alignment: .top) {
            // Drop indicator line
            if viewModel.draggingSlot != nil && viewModel.draggingSlot != slot {
                Rectangle()
                    .fill(DesignTokens.accentCyan)
                    .frame(height: 2)
                    .padding(.horizontal, DesignTokens.spacingLG)
            }
        }
        .onTapGesture {
            viewModel.selectedSlot = slot
            viewModel.showDetail = true
        }
        .onDrag {
            viewModel.draggingSlot = slot
            viewModel.draggingFromDay = dayNumber
            let data = "\(dayNumber)|\(slot.activityName)".data(using: .utf8) ?? Data()
            return NSItemProvider(item: data as NSData, typeIdentifier: "public.text")
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            // Drop indicator: accept drop at this position
            if let dragging = viewModel.draggingSlot,
               let fromDay = viewModel.draggingFromDay,
               fromDay == dayNumber {
                if let dayIdx = viewModel.itinerary.days.firstIndex(where: { $0.dayNumber == dayNumber }),
                   let fromIdx = viewModel.itinerary.days[dayIdx].slots.firstIndex(where: { $0 == dragging }),
                   let toIdx = viewModel.itinerary.days[dayIdx].slots.firstIndex(where: { $0 == slot }),
                   fromIdx != toIdx {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.itinerary.days[dayIdx].slots.move(
                            fromOffsets: IndexSet(integer: fromIdx),
                            toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx
                        )
                    }
                    viewModel.recalculateCost()
                }
            }
            viewModel.draggingSlot = nil
            viewModel.draggingFromDay = nil
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.timeSlot): \(slot.activityName), \(slot.estimatedDurationMin) minutes")
        .accessibilityHint("Tap for details. Long press to drag and reorder.")
    }

    // MARK: - Slot Actions (Req 5.5, 5.7)

    private func slotActions(slot: ItinerarySlot, dayNumber: Int) -> some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    await viewModel.replaceActivity(dayNumber: dayNumber, slot: slot)
                }
            } label: {
                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.accentCyan)
            }
            .disabled(viewModel.isReplacing)
            .accessibilityLabel("Replace \(slot.activityName)")

            Button(role: .destructive) {
                viewModel.removeActivity(from: dayNumber, slot: slot)
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.caption2)
            }
            .accessibilityLabel("Remove \(slot.activityName)")
        }
        .padding(.top, 4)
    }

    // MARK: - Restaurant Row

    private func restaurantRow(restaurant: ItineraryRestaurant) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(DesignTokens.accentCyan)
                    .font(.title3)
            }
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
                    Text(PriceFormatter.restaurantPriceFromTier(restaurant.priceLevel))
                    if restaurant.rating > 0 {
                        Label(String(format: "%.1f", restaurant.rating), systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.caption2)
                .foregroundStyle(DesignTokens.textSecondary)

                Text("Estimated")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textTertiary)

                // Origin label
                if let origin = restaurant.origin {
                    Text(origin == "user" ? "Selected by you" : "Suggested")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                } else {
                    Text("Suggested")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                }

                ExternalLinkButton(placeName: restaurant.name, city: viewModel.itinerary.destination)
            }
            .padding(.vertical, 8)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Restaurant: \(restaurant.name), \(restaurant.cuisine), rating \(String(format: "%.1f", restaurant.rating))")
    }

    // MARK: - Add Activity Button (Req 5.6)

    private func addActivityButton(dayNumber: Int) -> some View {
        Button {
            viewModel.addActivityDayNumber = dayNumber
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
        .accessibilityLabel("Add activity to Day \(dayNumber)")
    }

    // MARK: - Cross-day drop handler (Req 5.4)

    private func handleCrossDayDrop(providers: [NSItemProvider], targetDay: Int) -> Bool {
        guard let slot = viewModel.draggingSlot,
              let fromDay = viewModel.draggingFromDay else { return false }
        viewModel.moveSlotToDay(slot, fromDay: fromDay, toDay: targetDay)
        viewModel.draggingSlot = nil
        viewModel.draggingFromDay = nil
        return true
    }

    // MARK: - Replacing Overlay

    private var replacingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(DesignTokens.accentCyan)
                Text("Finding alternative…")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .padding(24)
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        }
    }

    // MARK: - Helpers

    private func timeSlotColor(_ timeSlot: String) -> Color {
        switch timeSlot.lowercased() {
        case "morning": return DesignTokens.accentCyan
        case "afternoon": return DesignTokens.accentBlue
        case "evening": return .purple
        default: return .gray
        }
    }
}



// MARK: - Slot Detail View (Req 5.2)

/// Sheet presenting activity details with map snippet, description, and duration.
/// Validates: Requirement 5.2
struct SlotDetailView: View {

    let slot: ItinerarySlot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Map snippet
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
                            detailRow(
                                icon: "location",
                                label: "Coordinates",
                                value: String(format: "%.4f, %.4f", slot.latitude, slot.longitude)
                            )
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

// MARK: - Add Activity Sheet (Req 5.6)

/// Sheet for adding a custom activity to a day.
/// Validates: Requirement 5.6
struct AddActivitySheet: View {

    let dayNumber: Int
    let onAdd: (String, String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var durationText: String = "60"

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (Int(durationText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Activity name", text: $name)
                        .accessibilityLabel("Activity name")
                    TextField("Description (optional)", text: $description)
                        .accessibilityLabel("Activity description")
                    TextField("Duration in minutes", text: $durationText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Duration in minutes")
                } header: {
                    Text("Add Activity to Day \(dayNumber)")
                }

                Section {
                    Button {
                        let duration = Int(durationText) ?? 60
                        onAdd(name.trimmingCharacters(in: .whitespaces), description, duration)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add Activity")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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
                    ItinerarySlot(timeSlot: "Evening", activityName: "Shibuya Crossing", description: "Experience the world's busiest pedestrian crossing", latitude: 35.6595, longitude: 139.7004, estimatedDurationMin: 60, travelTimeToNextMin: nil, estimatedCostUsd: 0)
                ],
                restaurant: ItineraryRestaurant(name: "Sushi Dai", cuisine: "Sushi", priceLevel: "$", rating: 4.7, latitude: 35.6655, longitude: 139.7710, imageUrl: nil, origin: "ai")
            ),
            ItineraryDay(
                dayNumber: 2,
                slots: [
                    ItinerarySlot(timeSlot: "Morning", activityName: "Meiji Shrine", description: "Peaceful Shinto shrine in a forested area", latitude: 35.6764, longitude: 139.6993, estimatedDurationMin: 90, travelTimeToNextMin: 10, estimatedCostUsd: 0),
                    ItinerarySlot(timeSlot: "Afternoon", activityName: "Harajuku & Takeshita Street", description: "Trendy fashion district with unique shops", latitude: 35.6702, longitude: 139.7026, estimatedDurationMin: 120, travelTimeToNextMin: nil, estimatedCostUsd: 30)
                ],
                restaurant: nil
            )
        ]
    )
    ItineraryView(itinerary: sampleItinerary)
}
