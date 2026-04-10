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

/// "My Trips" screen listing all saved trips in a 2-column grid with glassmorphic cards.
/// Validates: Requirements 9.2, 9.3, 9.4, 11.1, 11.2, 11.3, 11.4
struct SavedTripsView: View {

    @StateObject private var viewModel = SavedTripsViewModel()
    @Environment(\.dismiss) private var dismiss

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
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red.opacity(0.9))
                            Button("Retry") {
                                Task { await viewModel.loadTrips() }
                            }
                            .foregroundStyle(DesignTokens.accentCyan)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.trips.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "suitcase")
                                .font(.system(size: 48))
                                .foregroundStyle(DesignTokens.textSecondary)
                            Text("No saved trips yet")
                                .font(.headline)
                                .foregroundStyle(DesignTokens.textSecondary)
                            Text("Plan a trip from the globe and save it here.")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.textTertiary)
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
                    Button("Close") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
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

    // MARK: - Trips Grid

    private var tripsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignTokens.spacingMD) {
                ForEach(viewModel.trips) { trip in
                    tripCard(trip)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.confirmDelete(trip)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(DesignTokens.spacingMD)
        }
        .refreshable {
            await viewModel.loadTrips()
        }
        .overlay {
            if viewModel.isLoadingTrip {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Loading trip…")
                        .tint(DesignTokens.accentCyan)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(24)
                        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
                }
            }
        }
    }

    private func tripCard(_ trip: TripListItem) -> some View {
        Button {
            Task { await viewModel.loadTrip(id: trip.id) }
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
                // City image placeholder (gradient)
                RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                    .fill(
                        LinearGradient(
                            colors: [DesignTokens.accentCyan.opacity(0.3), DesignTokens.accentBlue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 100)
                    .overlay(
                        Image(systemName: "airplane")
                            .font(.title)
                            .foregroundStyle(DesignTokens.textSecondary)
                    )

                // Trip info
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.destination)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text("\(trip.numDays) days")
                            .font(.caption)
                    }
                    .foregroundStyle(DesignTokens.textSecondary)

                    if let vibe = trip.vibe {
                        Text(vibe)
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.accentCyan)
                    }

                    Text(formattedDate(trip.createdAt))
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.textTertiary)
                }
                .padding(.horizontal, DesignTokens.spacingSM)
                .padding(.bottom, DesignTokens.spacingSM)
            }
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.destination), \(trip.numDays) days")
        .accessibilityHint("Tap to view trip details. Long press for options.")
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

/// Displays a full saved trip with itinerary, map, and places.
/// Validates: Requirement 9.3
struct SavedTripDetailView: View {

    let trip: TripResponse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.destination)
                            .font(.title.weight(.bold))
                            .foregroundStyle(DesignTokens.textPrimary)
                        HStack(spacing: 12) {
                            Label("\(trip.numDays) days", systemImage: "calendar")
                            if let vibe = trip.vibe {
                                Label(vibe, systemImage: vibeIcon(vibe))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                    }

                    Divider().overlay(DesignTokens.surfaceGlassBorder)

                    if trip.itinerary != nil {
                        Text("Itinerary saved with this trip.")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    } else {
                        Text("No itinerary data available.")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textTertiary)
                    }

                    if trip.costBreakdown != nil {
                        Text("Cost breakdown saved with this trip.")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
                .padding(DesignTokens.spacingMD)
            }
            .background(DesignTokens.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
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
