import SwiftUI

// MARK: - Share Sheet View

struct ShareSheetView: View {

    let itinerary: ItineraryResponse
    @Binding var plannedBy: String
    var selectedHotel: PlaceRecommendation? = nil
    @State private var notes: String = ""
    @State private var showActivitySheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
                        Text("\(itinerary.numDays)-Day \(itinerary.destination) \(itinerary.vibes.joined(separator: " & ")) Trip")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DesignTokens.textPrimary)

                        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                            Text("Planned by (optional)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                            TextField("Your name or business", text: $plannedBy)
                                .textFieldStyle(.plain)
                                .font(.body)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(DesignTokens.spacingSM)
                                .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                                .onChange(of: plannedBy) { _, newValue in
                                    if newValue.count > 100 { plannedBy = String(newValue.prefix(100)) }
                                }
                        }

                        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                            Text("Add notes (optional)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                            ZStack(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("e.g. Book dinner in advance, Best time to visit is sunset")
                                        .font(.body)
                                        .foregroundStyle(DesignTokens.textTertiary)
                                        .padding(DesignTokens.spacingSM)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $notes)
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 44, maxHeight: 120)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(DesignTokens.spacingXS)
                                    .onChange(of: notes) { _, newValue in
                                        if newValue.count > 500 { notes = String(newValue.prefix(500)) }
                                    }
                            }
                            .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                        }

                        Button {
                            showActivitySheet = true
                        } label: {
                            Text("Share")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(DesignTokens.accentGradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
                        }
                        .accessibilityLabel("Share trip")
                    }
                    .padding(DesignTokens.spacingMD)
                }
            }
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignTokens.textPrimary)
                }
            }
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showActivitySheet) {
                ActivityViewControllerWrapper(
                    activityItems: [
                        ShareFormatter.formatTrip(
                            itinerary,
                            plannedBy: plannedBy.isEmpty ? nil : plannedBy,
                            notes: notes.isEmpty ? nil : notes,
                            hotel: selectedHotel
                        )
                    ]
                )
            }
        }
    }
}

#Preview {
    ShareSheetView(
        itinerary: ItineraryResponse(
            destination: "Tokyo",
            numDays: 3,
            vibes: ["Foodie"],
            budgetTier: "$$$",
            days: [],
            reasoningText: nil
        ),
        plannedBy: .constant(""),
        selectedHotel: nil
    )
}
