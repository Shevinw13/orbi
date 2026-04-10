import SwiftUI
import MapKit

// MARK: - CityMarker

struct CityMarker: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double

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

// MARK: - GlobeView (MapKit 3D Globe)

struct GlobeView: View {

    @Binding var selectedCity: CityMarker?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var cities: [CityMarker] = CityMarker.popularCities
    @Namespace private var mapScope
    @State private var currentDistance: Double = 20_000_000

    var body: some View {
        ZStack(alignment: .trailing) {
            Map(position: $mapPosition, scope: mapScope) {
                ForEach(cities) { city in
                    Annotation(city.name, coordinate: city.coordinate) {
                        CityPinView(city: city) {
                            selectCity(city)
                        }
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls {}

            // Zoom controls — right side
            VStack(spacing: 8) {
                Spacer()

                VStack(spacing: 0) {
                    Button {
                        zoomIn()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }

                    Divider()
                        .frame(width: 30)
                        .overlay(Color.white.opacity(0.2))

                    Button {
                        zoomOut()
                    } label: {
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
        }
        .onAppear {
            mapPosition = .camera(
                MapCamera(
                    centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 10),
                    distance: currentDistance,
                    heading: 0,
                    pitch: 0
                )
            )
        }
        .task {
            await loadPopularCities()
        }
        .onChange(of: selectedCity) { _, newCity in
            if let city = newCity {
                currentDistance = 500_000
                withAnimation(.easeInOut(duration: 1.2)) {
                    mapPosition = .camera(
                        MapCamera(
                            centerCoordinate: city.coordinate,
                            distance: 500_000,
                            heading: 0,
                            pitch: 45
                        )
                    )
                }
            }
        }
    }

    private func zoomIn() {
        currentDistance = max(1_000, currentDistance / 3)
        withAnimation(.easeInOut(duration: 0.5)) {
            mapPosition = .camera(
                MapCamera(
                    centerCoordinate: currentCenterOrDefault(),
                    distance: currentDistance,
                    heading: 0,
                    pitch: currentDistance < 100_000 ? 60 : 0
                )
            )
        }
    }

    private func zoomOut() {
        currentDistance = min(30_000_000, currentDistance * 3)
        withAnimation(.easeInOut(duration: 0.5)) {
            mapPosition = .camera(
                MapCamera(
                    centerCoordinate: currentCenterOrDefault(),
                    distance: currentDistance,
                    heading: 0,
                    pitch: 0
                )
            )
        }
    }

    private func currentCenterOrDefault() -> CLLocationCoordinate2D {
        if let city = selectedCity {
            return city.coordinate
        }
        return CLLocationCoordinate2D(latitude: 30, longitude: 10)
    }

    private func selectCity(_ city: CityMarker) {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        selectedCity = city
    }

    private func loadPopularCities() async {
        struct PopularCitiesResponse: Decodable {
            let results: [PopularCity]
        }
        struct PopularCity: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
        }
        do {
            let response: PopularCitiesResponse = try await APIClient.shared.request(
                .get, path: "/search/popular-cities", requiresAuth: false
            )
            let loaded = response.results.map {
                CityMarker(
                    name: $0.name.components(separatedBy: ",").first ?? $0.name,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
            if !loaded.isEmpty {
                cities = loaded
            }
        } catch {
            // Keep hardcoded fallback
        }
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
                // Pin dot
                ZStack {
                    // Glow
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

                // City name label
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
