import SwiftUI
import MapKit

// MARK: - Route Segment Model

/// Represents a calculated route segment between two consecutive activity stops.
struct RouteSegment: Identifiable {
    let id = UUID()
    let from: ItinerarySlot
    let to: ItinerarySlot
    let route: MKRoute
    let travelTimeMinutes: Int
    let distanceMeters: Double
    let transportType: MKDirectionsTransportType
}

// MARK: - Map Route ViewModel

/// Manages route calculation and map state for a single day's activities.
/// Validates: Requirements 6.1, 6.2, 6.3, 6.4
@MainActor
final class MapRouteViewModel: ObservableObject {

    @Published var slots: [ItinerarySlot]
    @Published var segments: [RouteSegment] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedSlot: ItinerarySlot?

    let dayNumber: Int

    init(day: ItineraryDay) {
        self.dayNumber = day.dayNumber
        self.slots = day.slots.filter { $0.latitude != 0 && $0.longitude != 0 }
    }

    /// Calculate routes between all consecutive activity stops.
    func calculateRoutes() async {
        guard slots.count >= 2 else { return }
        isLoading = true
        errorMessage = nil
        var computed: [RouteSegment] = []

        for i in 0..<(slots.count - 1) {
            let origin = slots[i]
            let destination = slots[i + 1]

            let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: origin.latitude, longitude: origin.longitude
            ))
            let destPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
                latitude: destination.latitude, longitude: destination.longitude
            ))

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: sourcePlacemark)
            request.destination = MKMapItem(placemark: destPlacemark)
            request.transportType = .walking

            let directions = MKDirections(request: request)

            do {
                let response = try await directions.calculate()
                if let route = response.routes.first {
                    let segment = RouteSegment(
                        from: origin,
                        to: destination,
                        route: route,
                        travelTimeMinutes: Int(route.expectedTravelTime / 60),
                        distanceMeters: route.distance,
                        transportType: .walking
                    )
                    computed.append(segment)
                }
            } catch {
                // Fall back to driving if walking fails
                request.transportType = .automobile
                let drivingDirections = MKDirections(request: request)
                do {
                    let response = try await drivingDirections.calculate()
                    if let route = response.routes.first {
                        let segment = RouteSegment(
                            from: origin,
                            to: destination,
                            route: route,
                            travelTimeMinutes: Int(route.expectedTravelTime / 60),
                            distanceMeters: route.distance,
                            transportType: .automobile
                        )
                        computed.append(segment)
                    }
                } catch {
                    // Skip this segment silently
                }
            }
        }

        segments = computed
        isLoading = false
    }

    /// Formatted distance string for a segment.
    func formattedDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

// MARK: - Map Route Polyline (UIKit overlay bridge)

/// UIViewRepresentable that draws MKRoute polylines on an MKMapView.
/// Validates: Requirement 6.2
struct MapRouteOverlay: UIViewRepresentable {

    let slots: [ItinerarySlot]
    let segments: [RouteSegment]
    let selectedSlot: Binding<ItinerarySlot?>

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // Add pin annotations for each slot (Req 6.1)
        for slot in slots {
            let annotation = SlotAnnotation(slot: slot)
            mapView.addAnnotation(annotation)
        }

        // Add route polylines (Req 6.2)
        for segment in segments {
            mapView.addOverlay(segment.route.polyline, level: .aboveRoads)
        }

        // Fit map to show all pins
        if !slots.isEmpty {
            let coordinates = slots.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            let region = regionForCoordinates(coordinates)
            mapView.setRegion(region, animated: false)
        }
    }

    private func regionForCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLng = coordinates[0].longitude
        var maxLng = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLng = min(minLng, coord.longitude)
            maxLng = max(maxLng, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.005,
            longitudeDelta: (maxLng - minLng) * 1.4 + 0.005
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapRouteOverlay

        init(parent: MapRouteOverlay) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let slotAnnotation = annotation as? SlotAnnotation else { return nil }

            let identifier = "SlotPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.canShowCallout = true
            view.markerTintColor = markerColor(for: slotAnnotation.slot.timeSlot)
            view.glyphImage = UIImage(systemName: "mappin")
            return view
        }

        /// Req 6.4 — pin tap shows activity name and scheduled time via callout
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let slotAnnotation = annotation as? SlotAnnotation else { return }
            parent.selectedSlot.wrappedValue = slotAnnotation.slot
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            parent.selectedSlot.wrappedValue = nil
        }

        private func markerColor(for timeSlot: String) -> UIColor {
            switch timeSlot.lowercased() {
            case "morning": return .systemOrange
            case "afternoon": return .systemBlue
            case "evening": return .systemPurple
            default: return .systemGray
            }
        }
    }
}


// MARK: - Slot Annotation

/// Custom MKAnnotation wrapping an ItinerarySlot for pin display.
/// Validates: Requirements 6.1, 6.4
final class SlotAnnotation: NSObject, MKAnnotation {
    let slot: ItinerarySlot

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: slot.latitude, longitude: slot.longitude)
    }

    /// Callout title shows activity name (Req 6.4)
    var title: String? { slot.activityName }

    /// Callout subtitle shows scheduled time (Req 6.4)
    var subtitle: String? { slot.timeSlot }

    init(slot: ItinerarySlot) {
        self.slot = slot
        super.init()
    }
}

// MARK: - Map Route View

/// Displays a day's activities as pins on a map with route polylines and segment details.
/// Validates: Requirements 6.1, 6.2, 6.3, 6.4
struct MapRouteView: View {

    @StateObject private var viewModel: MapRouteViewModel
    @Environment(\.dismiss) private var dismiss

    init(day: ItineraryDay) {
        _viewModel = StateObject(wrappedValue: MapRouteViewModel(day: day))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map with overlays (Req 6.1, 6.2)
                MapRouteOverlay(
                    slots: viewModel.slots,
                    segments: viewModel.segments,
                    selectedSlot: $viewModel.selectedSlot
                )
                .ignoresSafeArea(edges: .bottom)

                // Segment details panel (Req 6.3)
                if !viewModel.segments.isEmpty {
                    segmentDetailsPanel
                }

                if viewModel.isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Day \(viewModel.dayNumber) Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await viewModel.calculateRoutes()
            }
        }
    }

    // MARK: - Segment Details Panel (Req 6.3)

    private var segmentDetailsPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.segments) { segment in
                    segmentCard(segment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route segments")
    }

    private func segmentCard(_ segment: RouteSegment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // From → To
            HStack(spacing: 4) {
                Text(segment.from.activityName)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                Text(segment.to.activityName)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))

            Divider()

            // Transport type, time, distance
            HStack(spacing: 8) {
                Image(systemName: segment.transportType == .walking ? "figure.walk" : "car.fill")
                    .foregroundStyle(.orange)
                Text("\(segment.travelTimeMinutes) min")
                    .font(.subheadline.weight(.medium))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(viewModel.formattedDistance(segment.distanceMeters))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 200)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "From \(segment.from.activityName) to \(segment.to.activityName), " +
            "\(segment.travelTimeMinutes) minutes \(segment.transportType == .walking ? "walking" : "driving"), " +
            viewModel.formattedDistance(segment.distanceMeters)
        )
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.orange)
                Text("Calculating routes…")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleDay = ItineraryDay(
        dayNumber: 1,
        slots: [
            ItinerarySlot(timeSlot: "Morning", activityName: "Tsukiji Outer Market", description: "Explore fresh seafood stalls", latitude: 35.6654, longitude: 139.7707, estimatedDurationMin: 120, travelTimeToNextMin: 15, estimatedCostUsd: 20),
            ItinerarySlot(timeSlot: "Afternoon", activityName: "Senso-ji Temple", description: "Visit Tokyo's oldest temple", latitude: 35.7148, longitude: 139.7967, estimatedDurationMin: 90, travelTimeToNextMin: 20, estimatedCostUsd: 0),
            ItinerarySlot(timeSlot: "Evening", activityName: "Shibuya Crossing", description: "Experience the busiest crossing", latitude: 35.6595, longitude: 139.7004, estimatedDurationMin: 60, travelTimeToNextMin: nil, estimatedCostUsd: 0)
        ],
        restaurant: nil
    )
    MapRouteView(day: sampleDay)
}
