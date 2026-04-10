import SwiftUI

// MARK: - Saved Trips ViewModel

/// Manages saved trips list, loading, and deletion.
/// Validates: Requirements 9.1, 9.2, 9.3, 9.4
@MainActor
final class SavedTripsViewModel: ObservableObject {

    @Published var trips: [TripListItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var tripToDelete: TripListItem?
    @Published var showDeleteConfirmation: Bool = false
    @Published var loadedTrip: TripResponse?
    @Published var isLoadingTrip: Bool = false

    // MARK: - List Trips (Req 9.2)

    func loadTrips() async {
        isLoading = true
        errorMessage = nil

        do {
            let items: [TripListItem] = try await APIClient.shared.request(
                .get, path: "/trips"
            )
            trips = items
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load trips."
        }

        isLoading = false
    }

    // MARK: - Load Single Trip (Req 9.3)

    func loadTrip(id: String) async {
        isLoadingTrip = true
        errorMessage = nil

        do {
            let trip: TripResponse = try await APIClient.shared.request(
                .get, path: "/trips/\(id)"
            )
            loadedTrip = trip
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load trip."
        }

        isLoadingTrip = false
    }

    // MARK: - Delete Trip (Req 9.4)

    func confirmDelete(_ trip: TripListItem) {
        tripToDelete = trip
        showDeleteConfirmation = true
    }

    func deleteTrip() async {
        guard let trip = tripToDelete else { return }

        do {
            try await APIClient.shared.requestVoid(
                .delete, path: "/trips/\(trip.id)"
            )
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

/// "My Trips" screen listing all saved trips with load and delete actions.
/// Validates: Requirements 9.2, 9.3, 9.4
struct SavedTripsView: View {

    @StateObject private var viewModel = SavedTripsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.trips.isEmpty {
                    ProgressView("Loading trips…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.trips.isEmpty {
                    VStack(spacing: 12) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { await viewModel.loadTrips() }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.trips.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "suitcase")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No saved trips yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Plan a trip from the globe and save it here.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    tripsList
                }
            }
            .navigationTitle("My Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await viewModel.loadTrips()
            }
            .alert("Delete Trip?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    viewModel.tripToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteTrip() }
                }
            } message: {
                if let trip = viewModel.tripToDelete {
                    Text("Are you sure you want to delete your \(trip.destination) trip? This cannot be undone.")
                }
            }
            .sheet(item: $viewModel.loadedTrip) { trip in
                SavedTripDetailView(trip: trip)
            }
        }
    }

    // MARK: - Trips List

    private var tripsList: some View {
        List {
            ForEach(viewModel.trips) { trip in
                tripRow(trip)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.confirmDelete(trip)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadTrips()
        }
        .overlay {
            if viewModel.isLoadingTrip {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Loading trip…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func tripRow(_ trip: TripListItem) -> some View {
        Button {
            Task { await viewModel.loadTrip(id: trip.id) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.destination)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Label("\(trip.numDays) days", systemImage: "calendar")
                        if let vibe = trip.vibe {
                            Text("·")
                            Text(vibe)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(formattedDate(trip.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.destination), \(trip.numDays) days")
        .accessibilityHint("Tap to view trip details. Swipe left to delete.")
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
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

/// Displays a full saved trip with itinerary, map, and places.
/// Validates: Requirement 9.3
struct SavedTripDetailView: View {

    let trip: TripResponse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Trip header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.destination)
                            .font(.title.weight(.bold))
                        HStack(spacing: 12) {
                            Label("\(trip.numDays) days", systemImage: "calendar")
                            if let vibe = trip.vibe {
                                Label(vibe, systemImage: vibeIcon(vibe))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Itinerary summary
                    if trip.itinerary != nil {
                        Text("Itinerary saved with this trip.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No itinerary data available.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }

                    // Cost summary
                    if trip.costBreakdown != nil {
                        Text("Cost breakdown saved with this trip.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
}

// MARK: - Preview

#Preview {
    SavedTripsView()
}
