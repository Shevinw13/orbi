import SwiftUI

// MARK: - Explore Feed ViewModel

@MainActor
final class ExploreFeedViewModel: ObservableObject {

    @Published var sections: [ExploreSection] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [SharedItineraryCard] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    var isSearchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    func loadFeed() async {
        isLoading = true
        errorMessage = nil
        do {
            // Single call to get all itineraries, then split into sections client-side
            let all: ExploreFeedResponse = try await APIClient.shared.request(
                .get, path: "/shared-itineraries",
                queryItems: [URLQueryItem(name: "page_size", value: "50")],
                requiresAuth: false
            )

            var builtSections: [ExploreSection] = []
            
            // All items become "Browse All"
            if !all.items.isEmpty {
                builtSections.append(ExploreSection(id: "all", title: "Browse All", sectionType: "recent", items: all.items))
            }
            sections = builtSections
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load explore feed."
        }
        isLoading = false
    }

    func search() async {
        guard isSearchActive else {
            searchResults = []
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            var queryItems = [URLQueryItem(name: "destination", value: searchQuery)]
            queryItems.append(URLQueryItem(name: "page_size", value: "50"))
            let result: ExploreFeedResponse = try await APIClient.shared.request(
                .get, path: "/shared-itineraries",
                queryItems: queryItems,
                requiresAuth: false
            )
            searchResults = result.items
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Search failed."
        }
        isLoading = false
    }

    func refresh() async {
        if isSearchActive {
            await search()
        } else {
            await loadFeed()
        }
    }
}

// MARK: - Explore Feed View

struct ExploreFeedView: View {

    @StateObject private var viewModel = ExploreFeedViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    content
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.loadFeed() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: DesignTokens.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.textSecondary)
            TextField("Search destinations…", text: $viewModel.searchQuery)
                .foregroundStyle(DesignTokens.textPrimary)
                .autocorrectionDisabled()
                .onSubmit { Task { await viewModel.search() } }
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
        .padding(DesignTokens.spacingSM)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.sections.isEmpty && viewModel.searchResults.isEmpty {
            Spacer()
            ProgressView("Loading…")
                .tint(DesignTokens.accentCyan)
                .foregroundStyle(DesignTokens.textSecondary)
            Spacer()
        } else if let error = viewModel.errorMessage, viewModel.sections.isEmpty && viewModel.searchResults.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red.opacity(0.9))
                Button("Retry") { Task { await viewModel.refresh() } }
                    .foregroundStyle(DesignTokens.accentCyan)
            }
            Spacer()
        } else if viewModel.isSearchActive {
            searchResultsList
        } else if viewModel.sections.isEmpty {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer().frame(height: 60)
                    Image(systemName: "globe.americas")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignTokens.accentCyan.opacity(0.5))
                    Text("No itineraries yet")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Be the first to share a trip! Create an itinerary and publish it to Explore.")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .refreshable { await viewModel.refresh() }
        } else {
            sectionsFeed
        }
    }

    private var sectionsFeed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.spacingLG) {
                ForEach(viewModel.sections) { section in
                    sectionRow(section)
                }
            }
            .padding(.vertical, DesignTokens.spacingSM)
        }
        .refreshable { await viewModel.refresh() }
    }

    private func sectionRow(_ section: ExploreSection) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Text(section.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(.horizontal, DesignTokens.spacingMD)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DesignTokens.spacingSM) {
                    ForEach(section.items) { card in
                        NavigationLink(value: card.id) {
                            ItineraryCardView(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignTokens.spacingMD)
            }
        }
        .navigationDestination(for: String.self) { id in
            ItineraryDetailView(itineraryId: id)
        }
    }

    private var searchResultsList: some View {
        Group {
            if viewModel.searchResults.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(DesignTokens.textSecondary)
                    Text("No itineraries found")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Try a different destination")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.spacingSM) {
                        ForEach(viewModel.searchResults) { card in
                            NavigationLink(value: card.id) {
                                ItineraryCardView(card: card)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DesignTokens.spacingMD)
                    .navigationDestination(for: String.self) { id in
                        ItineraryDetailView(itineraryId: id)
                    }
                }
                .refreshable { await viewModel.refresh() }
            }
        }
    }
}

#Preview { ExploreFeedView() }
