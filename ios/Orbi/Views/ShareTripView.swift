import SwiftUI

// MARK: - Share Trip ViewModel

/// Manages share link generation and clipboard copy.
/// Validates: Requirements 10.1, 10.2
@MainActor
final class ShareTripViewModel: ObservableObject {

    @Published var isGenerating: Bool = false
    @Published var shareURL: String?
    @Published var errorMessage: String?
    @Published var copied: Bool = false

    let tripId: String

    init(tripId: String) {
        self.tripId = tripId
    }

    // MARK: - Generate Share Link (Req 10.1)

    func generateShareLink() async {
        isGenerating = true
        errorMessage = nil

        do {
            let response: ShareLinkResponse = try await APIClient.shared.request(
                .post, path: "/trips/\(tripId)/share"
            )
            shareURL = response.shareUrl
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to generate share link."
        }

        isGenerating = false
    }

    // MARK: - Copy to Clipboard (Req 10.1)

    func copyLink() {
        guard let url = shareURL else { return }
        UIPasteboard.general.string = url
        copied = true
        // Reset after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }
}

// MARK: - Share Trip Button

/// A button that generates a share link and copies it to the clipboard.
/// Validates: Requirements 10.1, 10.2
struct ShareTripButton: View {

    @StateObject private var viewModel: ShareTripViewModel

    init(tripId: String) {
        _viewModel = StateObject(wrappedValue: ShareTripViewModel(tripId: tripId))
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.generateShareLink()
                    if viewModel.shareURL != nil {
                        viewModel.copyLink()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: viewModel.copied ? "checkmark" : "square.and.arrow.up")
                    }
                    Text(viewModel.copied ? "Link Copied!" : "Share Trip")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.copied ? Color.green : Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(viewModel.isGenerating)
            .accessibilityLabel(viewModel.copied ? "Link copied to clipboard" : "Share trip")

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}


// MARK: - Shared Trip View (Read-Only)

/// Displays a read-only view of a shared trip loaded via deep link.
/// Validates: Requirements 10.2, 10.3, 10.4
struct SharedTripView: View {

    let shareId: String
    @State private var trip: SharedTripResponse?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading shared trip…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadSharedTrip() }
                        }
                    }
                    .padding(24)
                } else if let trip {
                    sharedTripContent(trip)
                }
            }
            .navigationTitle("Shared Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadSharedTrip()
            }
        }
    }

    private func loadSharedTrip() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: SharedTripResponse = try await APIClient.shared.request(
                .get, path: "/share/\(shareId)", requiresAuth: false
            )
            trip = response
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load shared trip."
        }

        isLoading = false
    }

    private func sharedTripContent(_ trip: SharedTripResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
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

                // Read-only badge
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                    Text("Read-only shared itinerary")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Divider()

                if trip.itinerary != nil {
                    Text("This trip includes a saved itinerary.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No itinerary data available.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if trip.costBreakdown != nil {
                    Text("Cost breakdown is included.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
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

#Preview("Share Button") {
    ShareTripButton(tripId: "test-trip-id")
        .padding()
}

#Preview("Shared Trip") {
    SharedTripView(shareId: "test-share-id")
}
