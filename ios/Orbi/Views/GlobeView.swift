import SwiftUI
import MapKit

// MARK: - CityMarker

struct CityMarker: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    var category: String?

    static func == (lhs: CityMarker, rhs: CityMarker) -> Bool {
        lhs.id == rhs.id
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let popularCities: [CityMarker] = [
        CityMarker(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        CityMarker(name: "Paris", latitude: 48.8566, longitude: 2.3522),
        CityMarker(name: "New York", latitude: 40.7128, longitude: -74.0060),
        CityMarker(name: "London", latitude: 51.5074, longitude: -0.1278),
        CityMarker(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
        CityMarker(name: "Dubai", latitude: 25.2048, longitude: 55.2708),
        CityMarker(name: "Rome", latitude: 41.9028, longitude: 12.4964),
        CityMarker(name: "Barcelona", latitude: 41.3874, longitude: 2.1686),
        CityMarker(name: "Rio de Janeiro", latitude: -22.9068, longitude: -43.1729),
    ]
}

// MARK: - ExploreFilterViewModel (Req 4.1, 4.2, 4.4)

@MainActor
final class ExploreFilterViewModel: ObservableObject {
    @Published var selectedCategory: ExploreCategory? = nil
    @Published var allCities: [CityMarker] = CityMarker.popularCities

    var filteredCities: [CityMarker] {
        guard let category = selectedCategory else { return allCities }
        return allCities.filter { $0.category?.lowercased() == category.rawValue.lowercased() }
    }

    func toggleFilter(_ category: ExploreCategory) {
        if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
        }
        Task { await loadCities(category: selectedCategory) }
    }

    func loadCities(category: ExploreCategory?) async {
        struct PopularCitiesResponse: Decodable {
            let results: [PopularCity]
        }
        struct PopularCity: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let category: String?
        }

        var queryItems: [URLQueryItem]? = nil
        if let cat = category {
            queryItems = [URLQueryItem(name: "category", value: cat.rawValue)]
        }

        do {
            let response: PopularCitiesResponse = try await APIClient.shared.request(
                .get, path: "/search/popular-cities", queryItems: queryItems, requiresAuth: false
            )
            let loaded = response.results.map {
                CityMarker(
                    name: $0.name.components(separatedBy: ",").first ?? $0.name,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    category: $0.category
                )
            }
            if !loaded.isEmpty {
                allCities = loaded
            }
        } catch {
            // Keep existing cities on error
        }
    }
}

// MARK: - ExploreOverlayViewModel (Req 2.1, 2.2, 2.3, 2.4, 2.5)

@MainActor
final class ExploreOverlayViewModel: ObservableObject {
    @Published var overlays: [ExploreOverlay] = []
    @Published var isLoading: Bool = false

    func loadOverlays(latitude: Double, longitude: Double) async {
        isLoading = true
        do {
            let response: ExploreOverlaysResponse = try await APIClient.shared.request(
                .get, path: "/explore/overlays",
                queryItems: [
                    URLQueryItem(name: "latitude", value: String(latitude)),
                    URLQueryItem(name: "longitude", value: String(longitude)),
                ],
                requiresAuth: false
            )
            overlays = response.overlays
        } catch {
            overlays = []
        }
        isLoading = false
    }
}

// MARK: - GlobeView (MapKit 3D Globe)

struct GlobeView: View {

    @Binding var selectedCity: CityMarker?
    var userLocation: CLLocationCoordinate2D?
    @StateObject private var filterVM = ExploreFilterViewModel()
    @StateObject private var overlayVM = ExploreOverlayViewModel()
    @State private var currentDistance: Double = 20_000_000

    var body: some View {
        ZStack(alignment: .top) {
            ClusterMapView(
                cities: filterVM.filteredCities,
                userLocation: userLocation,
                selectedCity: $selectedCity,
                cameraDistance: $currentDistance
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Category filter pills (Req 4.1, 4.2, 4.4)
                filterPillsRow
                    .padding(.top, 60)

                Spacer()

                // Explore overlay cards (Req 2.1, 2.4)
                if !overlayVM.overlays.isEmpty {
                    overlayCardsRow
                        .padding(.bottom, DesignTokens.tabBarHeight + 90)
                }
            }

            // Zoom controls — right side
            VStack(spacing: 8) {
                Spacer()
                VStack(spacing: 0) {
                    Button { zoomIn() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    Divider()
                        .frame(width: 30)
                        .overlay(Color.white.opacity(0.2))
                    Button { zoomOut() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .padding(.trailing, 12)
                .padding(.bottom, DesignTokens.tabBarHeight + 80)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .task {
            await filterVM.loadCities(category: nil)
            let loc = userLocation ?? LocationManager.defaultLocation
            await overlayVM.loadOverlays(latitude: loc.latitude, longitude: loc.longitude)
        }
    }

    // MARK: - Filter Pills Row

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.spacingSM) {
                ForEach(ExploreCategory.allCases) { category in
                    FilterPill(
                        category: category,
                        isSelected: filterVM.selectedCategory == category,
                        onTap: { filterVM.toggleFilter(category) }
                    )
                }
            }
            .padding(.horizontal, DesignTokens.spacingMD)
        }
    }

    // MARK: - Overlay Cards Row

    private var overlayCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.spacingSM) {
                ForEach(overlayVM.overlays) { overlay in
                    OverlayCard(overlay: overlay)
                }
            }
            .padding(.horizontal, DesignTokens.spacingMD)
        }
    }

    // MARK: - Zoom

    private func zoomIn() {
        currentDistance = max(1_000, currentDistance / 3)
    }

    private func zoomOut() {
        currentDistance = min(30_000_000, currentDistance * 3)
    }

    private func selectCity(_ city: CityMarker) {
        selectedCity = city
    }
}

// MARK: - Filter Pill (Req 4.1, 4.2)

struct FilterPill: View {
    let category: ExploreCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : DesignTokens.textSecondary)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(DesignTokens.accentGradient)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
            )
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(category.rawValue) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Overlay Card (Req 2.1, 2.4)

struct OverlayCard: View {
    let overlay: ExploreOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
            Text(overlay.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)
            ForEach(overlay.destinations.prefix(3), id: \.name) { dest in
                Text(dest.name)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
        .padding(DesignTokens.spacingSM)
        .frame(width: 160)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
    }
}

// MARK: - City Pin View (custom annotation)

struct CityPinView: View {
    let city: CityMarker
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(DesignTokens.accentCyan.opacity(0.3))
                        .frame(width: 28, height: 28)
                    Circle()
                        .fill(DesignTokens.accentCyan)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                }
                Text(city.name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            }
        }
        .scaleEffect(isPressed ? 1.3 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    GlobeView(selectedCity: .constant(nil))
        .ignoresSafeArea()
}
