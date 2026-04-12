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
    @State private var ripplePoint: CGPoint? = nil
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Task 17.1: Globe glow layer — radial gradient behind the map
            RadialGradient(
                colors: [
                    DesignTokens.accentBlue.opacity(0.25),
                    Color(red: 0.4, green: 0.2, blue: 0.6).opacity(0.20),
                    DesignTokens.accentCyan.opacity(0.15),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 400
            )
            .ignoresSafeArea()

            ClusterMapView(
                cities: filterVM.filteredCities,
                userLocation: userLocation,
                selectedCity: $selectedCity,
                cameraDistance: $currentDistance,
                onBackgroundTap: { point in
                    triggerRipple(at: point)
                }
            )
            .ignoresSafeArea()

            // Task 17.1: Landmass contrast — subtle gradient overlay at map edges
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [DesignTokens.backgroundPrimary.opacity(0.3), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .ignoresSafeArea()

                Spacer()

                LinearGradient(
                    colors: [Color.clear, DesignTokens.backgroundPrimary.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
            }
            .allowsHitTesting(false)

            // Task 17.4: Ripple feedback overlay
            if let point = ripplePoint {
                Circle()
                    .fill(DesignTokens.accentCyan)
                    .frame(width: 80 * rippleScale, height: 80 * rippleScale)
                    .opacity(rippleOpacity)
                    .position(point)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
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

    // MARK: - Ripple Animation (Task 17.4)

    private func triggerRipple(at point: CGPoint) {
        ripplePoint = point
        rippleScale = 0
        rippleOpacity = 0.3
        withAnimation(.easeOut(duration: 0.4)) {
            rippleScale = 1.0
            rippleOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ripplePoint = nil
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


// MARK: - City Annotation (MKClusterAnnotation-compatible)

final class CityAnnotation: MKPointAnnotation {
    let city: CityMarker
    init(city: CityMarker) {
        self.city = city
        super.init()
        self.coordinate = city.coordinate
        self.title = city.name
    }
}

// MARK: - ClusterMapView (UIViewRepresentable)

struct ClusterMapView: UIViewRepresentable {
    let cities: [CityMarker]
    var userLocation: CLLocationCoordinate2D?
    @Binding var selectedCity: CityMarker?
    @Binding var cameraDistance: Double
    var onBackgroundTap: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satelliteFlyover
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.showsCompass = false
        mapView.showsUserLocation = false
        mapView.register(CityAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(ClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        let center = userLocation ?? LocationManager.defaultLocation
        mapView.setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: cameraDistance, pitch: 0, heading: 0), animated: false)
        mapView.addAnnotations(cities.map { CityAnnotation(city: $0) })

        // Task 17.4: Tap gesture for ripple feedback
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleBackgroundTap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        // Task 17.2: Touch gesture for rotation pause/resume
        let touchGesture = GlobeRotationPanGesture(target: context.coordinator, action: #selector(Coordinator.handleTouch(_:)))
        touchGesture.delegate = context.coordinator
        touchGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(touchGesture)

        // Task 17.2: Start rotation timer
        context.coordinator.mapView = mapView
        context.coordinator.startRotationTimer()

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let existing = Set(mapView.annotations.compactMap { ($0 as? CityAnnotation)?.city.name })
        let new = Set(cities.map(\.name))
        if existing != new {
            mapView.removeAnnotations(mapView.annotations.filter { $0 is CityAnnotation })
            mapView.addAnnotations(cities.map { CityAnnotation(city: $0) })
        }
        if let city = selectedCity, context.coordinator.lastSelected != city.name {
            context.coordinator.lastSelected = city.name
            UIView.animate(withDuration: 1.2) {
                mapView.camera = MKMapCamera(lookingAtCenter: city.coordinate, fromDistance: 500_000, pitch: 45, heading: 0)
            }
        }
        let delta = abs(mapView.camera.centerCoordinateDistance - cameraDistance) / max(mapView.camera.centerCoordinateDistance, 1)
        if delta > 0.1 && context.coordinator.lastSelected == selectedCity?.name {
            UIView.animate(withDuration: 0.5) {
                mapView.camera = MKMapCamera(lookingAtCenter: mapView.camera.centerCoordinate, fromDistance: self.cameraDistance, pitch: self.cameraDistance < 100_000 ? 60 : 0, heading: mapView.camera.heading)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let parent: ClusterMapView
        var lastSelected: String?
        weak var mapView: MKMapView?

        // Task 17.2: Rotation state
        private var rotationTimer: Timer?
        private var resumeWorkItem: DispatchWorkItem?
        private var isRotationPaused = false
        private static let rotationInterval: TimeInterval = 1.0 / 30.0 // 30fps
        private static let degreesPerTick: Double = 2.0 / 30.0 // ~2°/sec

        init(parent: ClusterMapView) {
            self.parent = parent
            super.init()
        }

        deinit {
            rotationTimer?.invalidate()
            rotationTimer = nil
            resumeWorkItem?.cancel()
        }

        // MARK: - Rotation Timer (Task 17.2)

        func startRotationTimer() {
            rotationTimer?.invalidate()
            isRotationPaused = false
            rotationTimer = Timer.scheduledTimer(withTimeInterval: Self.rotationInterval, repeats: true) { [weak self] _ in
                guard let self, !self.isRotationPaused, let mapView = self.mapView else { return }
                let newHeading = mapView.camera.heading + Self.degreesPerTick
                let cam = MKMapCamera(
                    lookingAtCenter: mapView.camera.centerCoordinate,
                    fromDistance: mapView.camera.centerCoordinateDistance,
                    pitch: mapView.camera.pitch,
                    heading: newHeading.truncatingRemainder(dividingBy: 360)
                )
                mapView.camera = cam
            }
        }

        private func pauseRotation() {
            isRotationPaused = true
            resumeWorkItem?.cancel()
        }

        private func scheduleResumeRotation() {
            resumeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.isRotationPaused = false
            }
            resumeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        }

        // MARK: - Touch Handling (Task 17.2)

        @objc func handleTouch(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                pauseRotation()
            case .ended, .cancelled, .failed:
                scheduleResumeRotation()
            default:
                break
            }
        }

        // MARK: - Background Tap (Task 17.4)

        @objc func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)

            // Hit-test to exclude annotation views, cluster views, and UI controls
            if let hitView = mapView.hitTest(point, with: nil) {
                if hitView is MKAnnotationView || hitView.superview is MKAnnotationView {
                    return
                }
            }

            // Convert to the superview coordinate space for the SwiftUI overlay
            let pointInSuperview = mapView.convert(point, to: mapView.superview)
            parent.onBackgroundTap?(pointInSuperview)
        }

        // MARK: - Gesture Recognizer Delegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        // MARK: - Map Delegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation)
            }
            if annotation is CityAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation)
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }
            if let ca = annotation as? CityAnnotation {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.async { self.parent.selectedCity = ca.city }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async { self.parent.cameraDistance = mapView.camera.centerCoordinateDistance }
        }
    }
}

// MARK: - GlobeRotationPanGesture (Task 17.2)

/// A continuous gesture recognizer that tracks touch begin/end for rotation pause/resume.
final class GlobeRotationPanGesture: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }
}

// MARK: - CityAnnotationView

final class CityAnnotationView: MKAnnotationView {
    static let clusterID = "cityCluster"
    private let glowCircle = UIView() // Task 17.1: faint glow at city positions
    private let dotOuter = UIView()
    private let dotInner = UIView()
    private let dotCenter = UIView()
    private let nameLabel = UILabel()
    private let labelBG = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = Self.clusterID
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: 80, height: 60)
        centerOffset = CGPoint(x: 0, y: -30)
        backgroundColor = .clear

        // Task 17.1: Faint static glow circle at city annotation positions
        glowCircle.frame = CGRect(x: 16, y: -10, width: 48, height: 48)
        glowCircle.backgroundColor = UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 0.15)
        glowCircle.layer.cornerRadius = 24
        glowCircle.isUserInteractionEnabled = false
        addSubview(glowCircle)

        dotOuter.frame = CGRect(x: 26, y: 0, width: 28, height: 28)
        dotOuter.backgroundColor = UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 0.3)
        dotOuter.layer.cornerRadius = 14
        addSubview(dotOuter)
        dotInner.frame = CGRect(x: 33, y: 7, width: 14, height: 14)
        dotInner.backgroundColor = UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 1)
        dotInner.layer.cornerRadius = 7
        addSubview(dotInner)
        dotCenter.frame = CGRect(x: 37, y: 11, width: 6, height: 6)
        dotCenter.backgroundColor = .white
        dotCenter.layer.cornerRadius = 3
        addSubview(dotCenter)
        labelBG.frame = CGRect(x: 0, y: 32, width: 80, height: 22)
        labelBG.layer.cornerRadius = 11
        labelBG.clipsToBounds = true
        addSubview(labelBG)
        nameLabel.frame = labelBG.bounds
        nameLabel.textAlignment = .center
        nameLabel.font = .systemFont(ofSize: 10, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        labelBG.contentView.addSubview(nameLabel)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var annotation: MKAnnotation? { didSet {
        guard let ca = annotation as? CityAnnotation else { return }
        nameLabel.text = ca.city.name
        let w = max(40, min((ca.city.name as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold)]).width + 16, 120))
        labelBG.frame = CGRect(x: (80 - w) / 2, y: 32, width: w, height: 22)
        nameLabel.frame = labelBG.bounds
    }}
}

// MARK: - ClusterAnnotationView

final class ClusterAnnotationView: MKAnnotationView {
    private let circle = UIView()
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        centerOffset = CGPoint(x: 0, y: -24)
        backgroundColor = .clear
        circle.frame = bounds
        circle.layer.cornerRadius = 24
        circle.clipsToBounds = true
        circle.layer.borderWidth = 2
        circle.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        let g = CAGradientLayer()
        g.frame = circle.bounds
        g.colors = [UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 0.9).cgColor, UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.9).cgColor]
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        circle.layer.insertSublayer(g, at: 0)
        addSubview(circle)
        label.frame = circle.bounds
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .white
        circle.addSubview(label)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var annotation: MKAnnotation? { didSet {
        guard let c = annotation as? MKClusterAnnotation else { return }
        let n = c.memberAnnotations.count
        label.text = "\(n)"
        let s: CGFloat = n > 10 ? 56 : (n > 5 ? 52 : 48)
        frame = CGRect(x: 0, y: 0, width: s, height: s)
        centerOffset = CGPoint(x: 0, y: -s / 2)
        circle.frame = bounds
        circle.layer.cornerRadius = s / 2
        label.frame = circle.bounds
        (circle.layer.sublayers?.first as? CAGradientLayer)?.frame = circle.bounds
    }}
}
