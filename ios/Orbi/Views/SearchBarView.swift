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
                    .foregroundStyle(.secondary)

                TextField("Search destinations…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onChange(of: viewModel.query) { _, _ in
                        viewModel.onQueryChanged()
                    }
                    .accessibilityLabel("Search destinations")

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

            // Suggestions dropdown
            if viewModel.showSuggestions {
                suggestionsDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showSuggestions)
    }

    // MARK: - Suggestions Dropdown

    @ViewBuilder
    private var suggestionsDropdown: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching {
                ProgressView()
                    .padding()
            } else if viewModel.showNoResults {
                // Requirement 2.4
                Text("No destinations found")
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.orange)
                            Text(suggestion.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .accessibilityLabel("Select \(suggestion.name)")

                    if suggestion.id != viewModel.suggestions.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .padding(.top, 4)
    }

    // MARK: - Selection

    /// On selection, create a CityMarker and set the binding to trigger globe zoom.
    /// Requirements: 2.3
    private func selectSuggestion(_ suggestion: DestinationSuggestion) {
        let marker = CityMarker(
            name: suggestion.name,
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
        Color.black.ignoresSafeArea()
        VStack {
            SearchBarView(selectedCity: .constant(nil))
            Spacer()
        }
        .padding(.top, 60)
    }
}
