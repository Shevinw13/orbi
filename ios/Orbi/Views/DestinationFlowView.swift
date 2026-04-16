import SwiftUI
import UIKit

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
    @Published var selectedBudgetTier: BudgetTier = .comfortable
    @Published var selectedVibes: Set<TripVibe> = [.foodie]
    @Published var familyFriendly: Bool = false
    @Published var daysError: String?
    @Published var isLoading: Bool = false
    @Published var loadingMessage: String = "Generating your itinerary…"
    @Published var submissionError: String?
    @Published var generatedItinerary: ItineraryResponse?

    /// Guards against double-firing haptic feedback
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
        guard !selectedVibes.isEmpty else { return false }
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
            budgetTier: selectedBudgetTier.apiValue,
            vibes: selectedVibes.map(\.rawValue),
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

// MARK: - Destination Flow View

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
                        vibes: viewModel.selectedVibes.map(\.rawValue),
                        budgetTier: viewModel.selectedBudgetTier.apiValue
                    )
                }
            }
        }
    }

    // MARK: - Preferences Card

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

                    Divider().padding(.horizontal, 20)

                    // Budget Tier
                    budgetTierSection

                    Divider().padding(.horizontal, 20)

                    // Vibe (multi-select)
                    vibeSection

                    // Family Friendly
                    Toggle(isOn: $viewModel.familyFriendly) {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.and.child.holdinghands")
                                .foregroundStyle(.cyan)
                            Text("Family Friendly")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .tint(.cyan)
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)

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

    // MARK: - Budget Tier Section

    private var budgetTierSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Budget Tier")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ForEach(BudgetTier.allCases) { tier in
                    let isSelected = viewModel.selectedBudgetTier == tier
                    Button {
                        viewModel.selectedBudgetTier = tier
                    } label: {
                        Text(tier.apiValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Color(.systemGray6))
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Text(viewModel.selectedBudgetTier.label)
                .font(.caption)
                .foregroundStyle(.cyan)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Vibe Section (multi-select)

    private var vibeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vibe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if viewModel.selectedVibes.isEmpty {
                    Text("(select at least one)")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 8) {
                ForEach(TripVibe.allCases) { vibe in
                    let isSelected = viewModel.selectedVibes.contains(vibe)
                    Button {
                        if isSelected {
                            viewModel.selectedVibes.remove(vibe)
                        } else {
                            viewModel.selectedVibes.insert(vibe)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vibe.icon)
                                .font(.caption2)
                            Text(vibe.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color(.systemGray6))
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                        .shadow(color: isSelected ? .cyan.opacity(0.3) : .clear, radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
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

    // MARK: - Loading View

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
