import SwiftUI

// MARK: - Itinerary Detail ViewModel

@MainActor
final class ItineraryDetailViewModel: ObservableObject {

    @Published var detail: SharedItineraryDetail?
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    @Published var hasSaved: Bool = false
    @Published var errorMessage: String?
    @Published var saveError: String?

    func loadDetail(id: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result: SharedItineraryDetail = try await APIClient.shared.request(
                .get, path: "/shared-itineraries/\(id)", requiresAuth: false
            )
            detail = result
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load itinerary."
        }
        isLoading = false
    }

    func saveToMyTrips(id: String) async {
        isSaving = true
        saveError = nil
        do {
            let _: CopyResponse = try await APIClient.shared.request(
                .post, path: "/shared-itineraries/\(id)/copy"
            )
            hasSaved = true
        } catch let error as APIError {
            saveError = error.errorDescription
        } catch {
            saveError = "Failed to save itinerary."
        }
        isSaving = false
    }
}

// MARK: - Itinerary Detail View

struct ItineraryDetailView: View {

    let itineraryId: String
    @StateObject private var viewModel = ItineraryDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    private var decodedItinerary: ItineraryResponse? {
        guard let dict = viewModel.detail?.itinerary else { return nil }
        guard let data = try? JSONEncoder().encode(dict) else { return nil }
        // The stored itinerary was encoded with convertToSnakeCase from Swift,
        // so use convertFromSnakeCase to decode it back
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let result = try? decoder.decode(ItineraryResponse.self, from: data) {
            return result
        }
        // Fallback: try without snake_case conversion (in case it was stored as camelCase)
        return try? JSONDecoder().decode(ItineraryResponse.self, from: data)
    }

    var body: some View {
        ZStack {
            DesignTokens.backgroundPrimary.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("Loading…")
                    .tint(DesignTokens.accentCyan)
                    .foregroundStyle(DesignTokens.textSecondary)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red.opacity(0.9))
                    Button("Retry") { Task { await viewModel.loadDetail(id: itineraryId) } }
                        .foregroundStyle(DesignTokens.accentCyan)
                }
            } else if let detail = viewModel.detail {
                detailContent(detail)
            }
        }
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await viewModel.loadDetail(id: itineraryId) }
        .alert("Save Error", isPresented: .init(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("Retry") { Task { await viewModel.saveToMyTrips(id: itineraryId) } }
            Button("OK", role: .cancel) { viewModel.saveError = nil }
        } message: {
            Text(viewModel.saveError ?? "")
        }
    }

    private func detailContent(_ detail: SharedItineraryDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Cover photo
                detailCoverPhoto(detail)

                // Header info
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)

                    Text(detail.destination)
                        .font(.headline)
                        .foregroundStyle(DesignTokens.accentCyan)

                    HStack(spacing: 12) {
                        Label("\(detail.numDays) days", systemImage: "calendar")
                        Text(String(repeating: "$", count: detail.budgetLevel))
                            .foregroundStyle(.orange)
                        HStack(spacing: 2) {
                            Image(systemName: "bookmark.fill")
                            Text("\(detail.saveCount)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)

                    if let username = detail.creatorUsername {
                        Label("by \(username)", systemImage: "person.circle")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    Text(detail.description)
                        .font(.body)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.top, 4)
                }
                .padding(DesignTokens.spacingMD)

                Divider().overlay(DesignTokens.surfaceGlassBorder).padding(.horizontal, DesignTokens.spacingMD)

                // Day-by-day breakdown
                if let itinerary = decodedItinerary {
                    ForEach(itinerary.days) { day in
                        detailDaySection(day: day)
                    }
                } else {
                    Text("No itinerary data available.")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(DesignTokens.spacingLG)
                }

                // Save button
                saveButton
                    .padding(DesignTokens.spacingMD)
            }
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func detailCoverPhoto(_ detail: SharedItineraryDetail) -> some View {
        if let urlString = detail.coverPhotoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 200).clipped()
                default:
                    detailGradientPlaceholder
                }
            }
        } else {
            detailGradientPlaceholder
        }
    }

    private var detailGradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [DesignTokens.accentCyan.opacity(0.3), DesignTokens.accentBlue.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "airplane").font(.system(size: 40)).foregroundStyle(DesignTokens.textSecondary)
        }
        .frame(height: 200)
    }

    private func detailDaySection(day: ItineraryDay) -> some View {
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

            // Use time block ordering: Morning → Afternoon → Evening, activities before meals
            let items = day.timeBlockItems
            let blocks = ["Morning", "Afternoon", "Evening"]
            ForEach(blocks, id: \.self) { block in
                let blockItems = items.filter { $0.timeBlock == block }
                if !blockItems.isEmpty {
                    Text(block)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(timeSlotColor(block))
                        .padding(.horizontal, DesignTokens.spacingMD)
                        .padding(.top, DesignTokens.spacingSM)
                        .padding(.bottom, DesignTokens.spacingXS)

                    ForEach(Array(blockItems.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .activity(let slot):
                            detailSlotCard(slot: slot, isLast: index == blockItems.count - 1)
                        case .meal(let meal):
                            detailMealRow(meal: meal)
                        }
                    }
                }
            }
        }
    }

    private func detailSlotCard(slot: ItinerarySlot, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(timeSlotColor(slot.timeSlot)).frame(width: 12, height: 12)
                if !isLast { Rectangle().fill(DesignTokens.surfaceGlassBorder).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                Text(slot.timeSlot).font(.caption.weight(.semibold)).foregroundStyle(timeSlotColor(slot.timeSlot))
                Text(slot.activityName).font(.body.weight(.medium)).foregroundStyle(DesignTokens.textPrimary)
                Text(slot.description).font(.caption).foregroundStyle(DesignTokens.textSecondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(slot.estimatedDurationMin) min", systemImage: "clock")
                    if let cost = slot.estimatedCostUsd, cost > 0 { Label("$\(Int(cost))", systemImage: "dollarsign.circle") }
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

    private func detailMealRow(meal: MealSlot) -> some View {
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
            }
            .padding(.vertical, 8)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.spacingMD)
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.saveToMyTrips(id: itineraryId) }
        } label: {
            HStack(spacing: DesignTokens.spacingSM) {
                if viewModel.isSaving {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: viewModel.hasSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                Text(viewModel.hasSaved ? "Saved to My Trips" : "Save to My Trips")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(viewModel.hasSaved ? AnyShapeStyle(Color.green) : AnyShapeStyle(DesignTokens.accentGradient))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
            .shadow(color: DesignTokens.accentCyan.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(viewModel.isSaving || viewModel.hasSaved)
        .opacity(viewModel.isSaving ? 0.7 : 1)
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
