import SwiftUI

// MARK: - Price Range Options

/// Shared price range options for hotel and restaurant pickers.
enum PriceRange: String, CaseIterable, Identifiable {
    case budget = "$"
    case mid = "$$"
    case premium = "$$$"

    var id: String { rawValue }
}

// MARK: - Hotel Vibe Options

enum HotelVibe: String, CaseIterable, Identifiable {
    case none = ""
    case luxury = "luxury"
    case boutique = "boutique"
    case budget = "budget"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No preference"
        case .luxury: return "Luxury"
        case .boutique: return "Boutique"
        case .budget: return "Budget"
        }
    }
}

// MARK: - Trip Vibe Options

/// Validates: Requirement 3.4
enum TripVibe: String, CaseIterable, Identifiable {
    case foodie = "Foodie"
    case adventure = "Adventure"
    case relaxed = "Relaxed"
    case nightlife = "Nightlife"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .foodie: return "fork.knife"
        case .adventure: return "figure.hiking"
        case .relaxed: return "leaf.fill"
        case .nightlife: return "moon.stars.fill"
        }
    }
}

// MARK: - View Model

/// Manages preferences form state, validation, and API submission.
/// Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 15.2, 15.3
@MainActor
final class TripPreferencesViewModel: ObservableObject {

    // Form fields
    @Published var daysText: String = "3"
    @Published var hotelPriceRange: PriceRange = .mid
    @Published var hotelVibe: HotelVibe = .none
    @Published var restaurantPriceRange: PriceRange = .mid
    @Published var cuisineType: String = ""
    @Published var selectedVibe: TripVibe = .foodie

    // Validation
    @Published var daysError: String?

    // Submission state
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = "Generating your itinerary…"
    @Published var submissionError: String?
    @Published var generatedItinerary: ItineraryResponse?

    private let city: CityMarker

    init(city: CityMarker) {
        self.city = city
    }

    // MARK: - Validation (Requirements 3.2, 3.3)

    /// Validates the days field. Returns the parsed integer if valid, nil otherwise.
    func validateDays() -> Int? {
        let trimmed = daysText.trimmingCharacters(in: .whitespaces)

        guard let days = Int(trimmed) else {
            daysError = "Number of days must be a whole number."
            return nil
        }

        guard days >= 1, days <= 14 else {
            daysError = "Number of days must be between 1 and 14."
            return nil
        }

        daysError = nil
        return days
    }

    /// Whether the form can be submitted (no active loading, days is valid).
    var canSubmit: Bool {
        guard !isLoading else { return false }
        guard let days = Int(daysText.trimmingCharacters(in: .whitespaces)),
              days >= 1, days <= 14 else {
            return false
        }
        return true
    }

    // MARK: - Submission (Requirements 3.5, 15.2, 15.3)

    func submit() async {
        submissionError = nil

        guard let days = validateDays() else { return }

        let request = TripPreferencesRequest(
            destination: city.name,
            latitude: city.latitude,
            longitude: city.longitude,
            numDays: days,
            hotelPriceRange: hotelPriceRange.rawValue,
            hotelVibe: hotelVibe == .none ? nil : hotelVibe.rawValue,
            restaurantPriceRange: restaurantPriceRange.rawValue,
            cuisineType: cuisineType.isEmpty ? nil : cuisineType,
            vibe: selectedVibe.rawValue
        )

        isLoading = true
        loadingMessage = "Sending preferences…"

        do {
            // Progress feedback during generation (Requirement 15.3)
            try await Task.sleep(nanoseconds: 300_000_000)
            loadingMessage = "Generating your itinerary…"

            let response: ItineraryResponse = try await APIClient.shared.request(
                .post,
                path: "/trips/generate",
                body: request
            )

            generatedItinerary = response
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            submissionError = error.errorDescription
        } catch {
            isLoading = false
            submissionError = "Something went wrong. Please try again."
        }
    }
}


// MARK: - Destination Flow View

/// Entry point for the destination selection flow, presented after a city is selected
/// from the search bar or globe tap.
/// Validates: Requirements 2.3, 3.1, 3.2, 3.3, 3.4, 3.5, 15.2, 15.3
struct DestinationFlowView: View {

    let city: CityMarker
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TripPreferencesViewModel
    @State private var showTripResult: Bool = false

    init(city: CityMarker) {
        self.city = city
        _viewModel = StateObject(wrappedValue: TripPreferencesViewModel(city: city))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    loadingOverlay
                } else {
                    preferencesForm
                }
            }
            .navigationTitle(city.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.generatedItinerary != nil) { _, hasItinerary in
                if hasItinerary {
                    showTripResult = true
                }
            }
            .fullScreenCover(isPresented: $showTripResult) {
                if let itinerary = viewModel.generatedItinerary {
                    TripResultView(
                        itinerary: itinerary,
                        city: city,
                        hotelPriceRange: viewModel.hotelPriceRange.rawValue,
                        hotelVibe: viewModel.hotelVibe == .none ? nil : viewModel.hotelVibe.rawValue,
                        restaurantPriceRange: viewModel.restaurantPriceRange.rawValue,
                        cuisineType: viewModel.cuisineType.isEmpty ? nil : viewModel.cuisineType
                    )
                }
            }
        }
    }

    // MARK: - Preferences Form (Requirement 3.1)

    private var preferencesForm: some View {
        Form {
            // Header
            Section {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("Plan your trip to \(city.name)")
                        .font(.headline)
                }
                .listRowBackground(Color.clear)
            }

            // Days (Requirements 3.1, 3.2, 3.3)
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Number of Days")
                        .font(.subheadline.weight(.medium))
                    TextField("1–14", text: $viewModel.daysText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Number of days, 1 to 14")
                        .onChange(of: viewModel.daysText) { _, _ in
                            // Clear error on edit
                            viewModel.daysError = nil
                        }
                    if let error = viewModel.daysError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Validation error: \(error)")
                    }
                }
            } header: {
                Text("Trip Duration")
            }

            // Vibe (Requirement 3.4)
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select your travel style")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(TripVibe.allCases) { vibe in
                            vibeButton(vibe)
                        }
                    }
                }
            } header: {
                Text("Vibe")
            }

            // Hotel preferences (Requirement 3.1)
            Section {
                Picker("Price Range", selection: $viewModel.hotelPriceRange) {
                    ForEach(PriceRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .accessibilityLabel("Hotel price range")

                Picker("Vibe", selection: $viewModel.hotelVibe) {
                    ForEach(HotelVibe.allCases) { vibe in
                        Text(vibe.displayName).tag(vibe)
                    }
                }
                .accessibilityLabel("Hotel vibe preference")
            } header: {
                Text("Hotel Preferences")
            }

            // Restaurant preferences (Requirement 3.1)
            Section {
                Picker("Price Range", selection: $viewModel.restaurantPriceRange) {
                    ForEach(PriceRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .accessibilityLabel("Restaurant price range")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cuisine Type (optional)")
                        .font(.subheadline.weight(.medium))
                    TextField("e.g. Japanese, Italian", text: $viewModel.cuisineType)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Cuisine type, optional")
                }
            } header: {
                Text("Restaurant Preferences")
            }

            // Submission error
            if let error = viewModel.submissionError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }

            // Submit button (Requirements 3.3, 3.5)
            Section {
                Button {
                    Task {
                        await viewModel.submit()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Generate Itinerary")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityLabel("Generate itinerary")
                .accessibilityHint(viewModel.canSubmit ? "Submits your trip preferences" : "Fix validation errors to submit")
            }
        }
    }

    // MARK: - Vibe Button

    private func vibeButton(_ vibe: TripVibe) -> some View {
        Button {
            viewModel.selectedVibe = vibe
        } label: {
            VStack(spacing: 6) {
                Image(systemName: vibe.icon)
                    .font(.title3)
                Text(vibe.rawValue)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                viewModel.selectedVibe == vibe
                    ? Color.orange.opacity(0.15)
                    : Color(.systemGray6)
            )
            .foregroundStyle(viewModel.selectedVibe == vibe ? .orange : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(viewModel.selectedVibe == vibe ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vibe.rawValue) vibe")
        .accessibilityAddTraits(viewModel.selectedVibe == vibe ? .isSelected : [])
    }

    // MARK: - Loading Overlay (Requirement 15.3)

    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.orange)

            Text(viewModel.loadingMessage)
                .font(.headline)
                .foregroundStyle(.primary)

            Text("This may take up to 15 seconds")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading. \(viewModel.loadingMessage)")
    }
}

// MARK: - Preview

#Preview {
    DestinationFlowView(
        city: CityMarker(name: "Tokyo", latitude: 35.6762, longitude: 139.6503)
    )
}
