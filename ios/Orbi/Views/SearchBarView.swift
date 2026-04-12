import SwiftUI
import Combine

// MARK: - Search View Model

/// Manages debounced autocomplete logic for destination search.
/// Requirements: 2.1, 2.2, 2.4
@MainActor
final class SearchViewModel: ObservableObject {

    @Published var query: String = ""
    @Published var suggestions: [DestinationSuggestion] = []
    @Published var showNoResults: Bool = false
    @Published var isSearching: Bool = false

    /// Controls whether the suggestions dropdown is visible.
    @Published var showSuggestions: Bool = false

    private var debounceTask: Task<Void, Never>?

    init() {
        // Observe query changes for debounced search
    }

    /// Called whenever the query text changes. Debounces at 300ms, triggers after 2+ chars.
    /// Requirements: 2.2
    func onQueryChanged() {
        debounceTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard trimmed.count >= 2 else {
            suggestions = []
            showNoResults = false
            showSuggestions = false
            isSearching = false
            return
        }

        showSuggestions = true
        debounceTask = Task {
            // 300ms debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    private func performSearch(_ text: String) async {
        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await SearchService.shared.searchDestinations(query: text)
            guard !Task.isCancelled else { return }
            suggestions = results
            showNoResults = results.isEmpty
        } catch {
            guard !Task.isCancelled else { return }
            suggestions = []
            showNoResults = true
        }
    }

    /// Resets the search state after a selection is made.
    func reset() {
        query = ""
        suggestions = []
        showNoResults = false
        showSuggestions = false
        debounceTask?.cancel()
    }
}


// MARK: - Search Bar View

/// Floating search bar overlay with debounced autocomplete and suggestions dropdown.
/// Requirements: 2.1, 2.2, 2.3, 2.4
struct SearchBarView: View {

    /// Binding to communicate the selected city back to the parent (triggers globe zoom).
    @Binding var selectedCity: CityMarker?

    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Search text field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.6))

                TextField("Search destinations…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .onChange(of: viewModel.query) { _, _ in
                        viewModel.onQueryChanged()
                    }
                    .accessibilityLabel("Search destinations")

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .accessibilityLabel("Clear search")
                }

                Spacer()

                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(height: DesignTokens.searchBarHeight)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusMD)
                    .stroke(DesignTokens.surfaceGlassBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)

            // Suggestions dropdown
            if viewModel.showSuggestions {
                suggestionsDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showSuggestions)
    }

    // MARK: - Suggestions Dropdown

    @ViewBuilder
    private var suggestionsDropdown: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching {
                ProgressView()
                    .tint(DesignTokens.accentCyan)
                    .padding()
            } else if viewModel.showNoResults {
                // Requirement 2.4
                Text("No destinations found")
                    .foregroundStyle(DesignTokens.textSecondary)
                    .font(.subheadline)
                    .padding()
                    .accessibilityLabel("No destinations found")
            } else {
                ForEach(viewModel.suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(DesignTokens.accentCyan)
                            Text(suggestion.name)
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .accessibilityLabel("Select \(suggestion.name)")

                    if suggestion.id != viewModel.suggestions.last?.id {
                        Divider()
                            .overlay(DesignTokens.surfaceGlassBorder)
                            .padding(.leading, 40)
                    }
                }
            }
        }
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        .padding(.top, DesignTokens.spacingXS)
    }

    // MARK: - Selection

    private func selectSuggestion(_ suggestion: DestinationSuggestion) {
        let marker = CityMarker(
            name: suggestion.name.components(separatedBy: ",").first ?? suggestion.name,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude
        )
        viewModel.reset()
        selectedCity = marker
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        DesignTokens.backgroundPrimary.ignoresSafeArea()
        VStack {
            SearchBarView(selectedCity: .constant(nil))
            Spacer()
        }
        .padding(.top, 60)
    }
}
