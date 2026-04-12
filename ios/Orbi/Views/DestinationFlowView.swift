import SwiftUI
import UIKit

// MARK: - Price Range Options

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

@MainActor
final class TripPreferencesViewModel: ObservableObject {

    @Published var daysText: String = "5"
    @Published var hotelPriceRange: PriceRange = .premium
    @Published var hotelVibe: HotelVibe = .none
    @Published var restaurantPriceRange: PriceRange = .mid
    @Published var cuisineType: String = ""
    @Published var selectedVibe: TripVibe = .foodie
    @Published var familyFriendly: Bool = false
    @Published var daysError: String?
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = "Generating your itinerary…"
    @Published var submissionError: String?
    @Published var generatedItinerary: ItineraryResponse?

    /// Guards against double-firing haptic feedback (Req 16.4)
    private var didFireHaptic: Bool = false

    let city: CityMarker

    init(city: CityMarker) {
        self.city = city
    }

    func validateDays() -> Int? {
        let trimmed = daysText.trimmingCharacters(in: .whitespaces)
        guard let days = Int(trimmed) else {
            daysError = "Must be a whole number."
            return nil
        }
        guard days >= 1, days <= 14 else {
            daysError = "Must be between 1 and 14."
            return nil
        }
        daysError = nil
        return days
    }

    var canSubmit: Bool {
        guard !isLoading else { return false }
        guard let days = Int(daysText.trimmingCharacters(in: .whitespaces)),
              days >= 1, days <= 14 else { return false }
        return true
    }

    func submit() async {
        submissionError = nil
        didFireHaptic = false
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
            vibe: selectedVibe.rawValue,
            familyFriendly: familyFriendly
        )

        isLoading = true
        loadingMessage = "Sending preferences…"

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            loadingMessage = "Generating your itinerary…"
            let response: ItineraryResponse = try await APIClient.shared.request(
                .post, path: "/trips/generate", body: request
            )
            generatedItinerary = response
            // Haptic feedback on successful itinerary generation (Req 16.1)
            if !didFireHaptic {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                didFireHaptic = true
            }
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

// MARK: - Destination Flow View (matches mockup)

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
                    loadingView
                } else {
                    preferencesCard
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
            .onChange(of: viewModel.generatedItinerary != nil) { _, has in
                if has { showTripResult = true }
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

    // MARK: - Preferences Card (mockup style)

    private var preferencesCard: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with city pin
                VStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.cyan)

                    Text(city.name)
                        .font(.title.weight(.bold))

                    Text("Plan a trip to \(city.name)?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Form fields
                VStack(spacing: 20) {
                    // Trip Length
                    preferenceRow(label: "Trip Length") {
                        HStack {
                            TextField("5", text: $viewModel.daysText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 40)
                            Text("Days")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let error = viewModel.daysError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }

                    // Hotel Preferences
                    preferenceRow(label: "Hotel Preferences") {
                        HStack(spacing: 4) {
                            Text(viewModel.hotelPriceRange.rawValue)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Hotel price pills
                    HStack(spacing: 8) {
                        ForEach(PriceRange.allCases) { range in
                            pillButton(
                                title: range.rawValue,
                                isSelected: viewModel.hotelPriceRange == range
                            ) {
                                viewModel.hotelPriceRange = range
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Divider().padding(.horizontal, 20)

                    // Vibe
                    Text("Vibe")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    HStack(spacing: 8) {
                        ForEach(TripVibe.allCases) { vibe in
                            pillButton(
                                title: vibe.rawValue,
                                isSelected: viewModel.selectedVibe == vibe
                            ) {
                                viewModel.selectedVibe = vibe
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)

                // Error
                if let error = viewModel.submissionError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                        .padding(.horizontal, 20)
                }

                // Generate button
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Generate Itinerary")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.5)
                .padding(.horizontal, 16)
                .padding(.top, 20)

                // Subtitle
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("Our travel experts are crafting your perfect itinerary")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Preference Row

    private func preferenceRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            content()
                .font(.subheadline)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Pill Button

    private func pillButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.cyan.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(isSelected ? .cyan : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading View (mockup: globe with generating text)

    private var loadingView: some View {
        ZStack {
            Color(red: 0.03, green: 0.03, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.cyan.opacity(0.6))

                VStack(spacing: 8) {
                    Text("Generating\nyour itinerary...")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                    Text("Our travel professionals are planning your perfect trip")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }

                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(1.2)

                Spacer()
            }
        }
    }
}

#Preview {
    DestinationFlowView(
        city: CityMarker(name: "Paris", latitude: 48.8566, longitude: 2.3522)
    )
}
