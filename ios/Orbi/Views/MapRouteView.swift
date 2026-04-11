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

    /// Total distance across all segments in meters.
    var totalDistance: Double {
        segments.reduce(0) { $0 + $1.distanceMeters }
    }

    /// Total travel time across all segments in minutes.
    var totalTime: Int {
        segments.reduce(0) { $0 + $1.travelTimeMinutes }
    }

    /// Walking time total in minutes (Req 9.3).
    var walkingTime: Int {
        segments.filter { $0.transportType == .walking }.reduce(0) { $0 + $1.travelTimeMinutes }
    }

    /// Driving time total in minutes (Req 9.3).
    var drivingTime: Int {
        segments.filter { $0.transportType == .automobile }.reduce(0) { $0 + $1.travelTimeMinutes }
    }

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
                    let walkingMinutes = Int(route.expectedTravelTime / 60)
                    let segment = RouteSegment(
                        from: origin,
                        to: destination,
                        route: route,
                        travelTimeMinutes: walkingMinutes,
                        distanceMeters: route.distance,
                        transportType: .walking
                    )
                    computed.append(segment)

                    // Req 9.4: If walking > 30 min, also calculate driving alternative
                    if walkingMinutes > 30 {
                        let drivingRequest = MKDirections.Request()
                        drivingRequest.source = MKMapItem(placemark: sourcePlacemark)
                        drivingRequest.destination = MKMapItem(placemark: destPlacemark)
                        drivingRequest.transportType = .automobile
                        let drivingDirections = MKDirections(request: drivingRequest)
                        if let drivingResponse = try? await drivingDirections.calculate(),
                           let drivingRoute = drivingResponse.routes.first {
                            let drivingSegment = RouteSegment(
                                from: origin,
                                to: destination,
                                route: drivingRoute,
                                travelTimeMinutes: Int(drivingRoute.expectedTravelTime / 60),
                                distanceMeters: drivingRoute.distance,
                                transportType: .automobile
                            )
                            computed.append(drivingSegment)
                        }
                    }
                }
            } catch {
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
/// Validates: Requirement 6.2, 9.2, 9.3
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
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // Add numbered pin annotations for each slot
        for (index, slot) in slots.enumerated() {
            let annotation = SlotAnnotation(slot: slot)
            annotation.stopNumber = index + 1
            mapView.addAnnotation(annotation)
        }

        // Add route polylines with blue stroke
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
                renderer.strokeColor = UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0) // DesignTokens.accentBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let slotAnnotation = annotation as? SlotAnnotation else { return nil }

            let identifier = "NumberedPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.canShowCallout = true

            // Create numbered circle view
            let size: CGFloat = 32
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
                // Circle background with time-slot color
                let color = markerColor(for: slotAnnotation.slot.timeSlot)
                color.setFill()
                ctx.cgContext.fillEllipse(in: rect)

                // Number text
                let number = "\(slotAnnotation.stopNumber)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.white
                ]
                let textSize = (number as NSString).size(withAttributes: attrs)
                let textRect = CGRect(
                    x: (size - textSize.width) / 2,
                    y: (size - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (number as NSString).draw(in: textRect, withAttributes: attrs)
            }

            view.image = image
            view.frame.size = CGSize(width: size, height: size)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let slotAnnotation = annotation as? SlotAnnotation else { return }
            parent.selectedSlot.wrappedValue = slotAnnotation.slot
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            parent.selectedSlot.wrappedValue = nil
        }

        private func markerColor(for timeSlot: String) -> UIColor {
            switch timeSlot.lowercased() {
            case "morning": return UIColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 1.0)
            case "afternoon": return UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
            case "evening": return .systemPurple
            default: return .systemGray
            }
        }
    }
}


// MARK: - Slot Annotation

/// Custom MKAnnotation wrapping an ItinerarySlot for pin display.
/// Validates: Requirements 6.1, 6.4, 9.3
final class SlotAnnotation: NSObject, MKAnnotation {
    let slot: ItinerarySlot
    var stopNumber: Int = 0

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: slot.latitude, longitude: slot.longitude)
    }

    var title: String? { slot.activityName }
    var subtitle: String? { slot.timeSlot }

    init(slot: ItinerarySlot) {
        self.slot = slot
        super.init()
    }
}


// MARK: - Map Route View

/// Displays a day's activities as pins on a map with route polylines and segment details.
/// Validates: Requirements 6.1, 6.2, 6.3, 6.4, 9.2, 9.3, 9.5, 9.6
struct MapRouteView: View {

    @StateObject private var viewModel: MapRouteViewModel
    @Environment(\.dismiss) private var dismiss

    init(day: ItineraryDay) {
        _viewModel = StateObject(wrappedValue: MapRouteViewModel(day: day))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map with overlays
                MapRouteOverlay(
                    slots: viewModel.slots,
                    segments: viewModel.segments,
                    selectedSlot: $viewModel.selectedSlot
                )
                .ignoresSafeArea(edges: .bottom)

                // Bottom panel: route summary + stop list
                if !viewModel.segments.isEmpty {
                    VStack(spacing: 0) {
                        routeSummaryCard
                        stopListView
                    }
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

    // MARK: - Route Summary Card

    private var routeSummaryCard: some View {
        HStack(spacing: DesignTokens.spacingSM) {
            VStack(spacing: 4) {
                Image(systemName: "map")
                    .foregroundStyle(DesignTokens.accentCyan)
                Text("Distance")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(viewModel.formattedDistance(viewModel.totalDistance))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Divider()
                .frame(height: 40)
                .overlay(DesignTokens.surfaceGlassBorder)

            VStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundStyle(DesignTokens.accentCyan)
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text("\(viewModel.totalTime) min")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Divider()
                .frame(height: 40)
                .overlay(DesignTokens.surfaceGlassBorder)

            VStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(DesignTokens.accentCyan)
                Text("Walking")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text("\(viewModel.walkingTime) min")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Divider()
                .frame(height: 40)
                .overlay(DesignTokens.surfaceGlassBorder)

            VStack(spacing: 4) {
                Image(systemName: "car")
                    .foregroundStyle(DesignTokens.accentCyan)
                Text("Driving")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text("\(viewModel.drivingTime) min")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            Divider()
                .frame(height: 40)
                .overlay(DesignTokens.surfaceGlassBorder)

            VStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(DesignTokens.accentCyan)
                Text("Stops")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.textSecondary)
                Text("\(viewModel.slots.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
        }
        .padding(DesignTokens.spacingSM)
        .frame(maxWidth: .infinity)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        .padding(.horizontal, DesignTokens.spacingMD)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Route summary: \(viewModel.formattedDistance(viewModel.totalDistance)), \(viewModel.totalTime) minutes total, \(viewModel.walkingTime) walking, \(viewModel.drivingTime) driving, \(viewModel.slots.count) stops")
    }

    // MARK: - Stop List

    private var stopListView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.spacingSM) {
                ForEach(Array(viewModel.slots.enumerated()), id: \.element.id) { index, slot in
                    stopCard(slot: slot, index: index)
                }
            }
            .padding(.horizontal, DesignTokens.spacingMD)
            .padding(.vertical, DesignTokens.spacingSM)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route stops")
    }

    private func stopCard(slot: ItinerarySlot, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(timeSlotColor(slot.timeSlot))
                    .clipShape(Circle())
                Text(slot.activityName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
            }

            if index < viewModel.segments.count {
                let segment = viewModel.segments[index]
                HStack(spacing: 4) {
                    Image(systemName: segment.transportType == .walking ? "figure.walk" : "car")
                        .font(.caption2)
                    Text(viewModel.formattedDistance(segment.distanceMeters))
                        .font(.caption2)
                    Text("· \(segment.travelTimeMinutes) min")
                        .font(.caption2)
                }
                .foregroundStyle(DesignTokens.textSecondary)

                // Ride-hail cost for walking segments > 15 min (Req 10.1, 10.2)
                if segment.transportType == .walking && segment.travelTimeMinutes > 15 {
                    let costRange = RideHailEstimator.estimate(distanceMeters: segment.distanceMeters)
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .font(.caption2)
                        Text("$\(Int(costRange.lowerBound))–$\(Int(costRange.upperBound))")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(DesignTokens.accentCyan)
                }
            }
        }
        .padding(DesignTokens.spacingSM)
        .frame(minWidth: 140)
        .glassmorphic(cornerRadius: DesignTokens.radiusSM)
    }

    private func timeSlotColor(_ timeSlot: String) -> Color {
        switch timeSlot.lowercased() {
        case "morning": return DesignTokens.accentCyan
        case "afternoon": return DesignTokens.accentBlue
        case "evening": return .purple
        default: return .gray
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(DesignTokens.accentCyan)
                Text("Calculating routes…")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .padding(24)
            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
        }
    }
}

// MARK: - RideHailEstimator (Req 10.1, 10.2, 10.3, 10.4)

/// Estimates ride-hail costs using base fare + per-km rate with 0.8x–1.5x range.
struct RideHailEstimator {
    struct CityRate {
        let baseFare: Double
        let perKmRate: Double
    }

    static let defaultRate = CityRate(baseFare: 3.0, perKmRate: 1.5)

    static let cityRates: [String: CityRate] = [
        "tokyo": CityRate(baseFare: 4.0, perKmRate: 2.0),
        "paris": CityRate(baseFare: 3.5, perKmRate: 1.8),
        "new york": CityRate(baseFare: 3.0, perKmRate: 2.5),
        "london": CityRate(baseFare: 4.0, perKmRate: 2.2),
        "dubai": CityRate(baseFare: 2.0, perKmRate: 1.0),
        "bangkok": CityRate(baseFare: 1.0, perKmRate: 0.5),
        "rome": CityRate(baseFare: 3.5, perKmRate: 1.5),
        "barcelona": CityRate(baseFare: 3.0, perKmRate: 1.3),
    ]

    static func estimate(distanceMeters: Double, city: String = "") -> ClosedRange<Double> {
        let rate = cityRates[city.lowercased()] ?? defaultRate
        let distanceKm = distanceMeters / 1000.0
        let low = rate.baseFare + distanceKm * rate.perKmRate * 0.8
        let high = rate.baseFare + distanceKm * rate.perKmRate * 1.5
        return low...high
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
