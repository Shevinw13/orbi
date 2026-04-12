import SwiftUI

// MARK: - Share Sheet View

/// Modal sheet presented before sharing, allowing optional "Planned by" and "Notes" inputs.
/// Validates: Requirements 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4
struct ShareSheetView: View {

    let itinerary: ItineraryResponse
    @Binding var plannedBy: String
    @State private var notes: String = ""
    @State private var showActivitySheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
                        // Trip title
                        Text("\(itinerary.numDays)-Day \(itinerary.destination) \(itinerary.vibe) Trip")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DesignTokens.textPrimary)

                        // Planned by field (Req 2.1, 2.2, 2.3)
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
                                    if newValue.count > 100 {
                                        plannedBy = String(newValue.prefix(100))
                                    }
                                }
                        }

                        // Notes field (Req 3.1, 3.2, 3.3, 3.4, 3.5)
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
                                        if newValue.count > 500 {
                                            notes = String(newValue.prefix(500))
                                        }
                                    }
                            }
                            .glassmorphic(cornerRadius: DesignTokens.radiusSM)
                        }

                        // Share button (Req 1.3, 4.1)
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
                            notes: notes.isEmpty ? nil : notes
                        )
                    ]
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ShareSheetView(
        itinerary: ItineraryResponse(
            destination: "Tokyo",
            numDays: 3,
            vibe: "Foodie",
            days: [],
            reasoningText: nil
        ),
        plannedBy: .constant("")
    )
}
