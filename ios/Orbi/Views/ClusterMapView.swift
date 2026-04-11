import SwiftUI
import MapKit

// MARK: - City Annotation (MKClusterAnnotation-compatible)

/// Custom annotation for city markers that supports MKMapView clustering.
/// Validates: Requirements 3.1, 3.2, 3.3, 3.4, 19.4
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

/// MKMapView-based map with native MKClusterAnnotation support for the Explore tab.
/// Replaces the SwiftUI `Map` to enable marker clustering at low zoom levels.
/// Validates: Requirements 3.1, 3.2, 3.3, 3.4, 19.4
struct ClusterMapView: UIViewRepresentable {
    let cities: [CityMarker]
    var userLocation: CLLocationCoordinate2D?
    @Binding var selectedCity: CityMarker?
    @Binding var cameraDistance: Double

    // MARK: - Make

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satelliteFlyover
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.showsCompass = false
        mapView.showsUserLocation = false

        // Register annotation views for clustering
        mapView.register(
            CityAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        mapView.register(
            ClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )

        // Set initial camera
        let center = userLocation ?? LocationManager.defaultLocation
        let camera = MKMapCamera(
            lookingAtCenter: center,
            fromDistance: cameraDistance,
            pitch: 0,
            heading: 0
        )
        mapView.setCamera(camera, animated: false)

        // Add city annotations
        let annotations = cities.map { CityAnnotation(city: $0) }
        mapView.addAnnotations(annotations)

        return mapView
    }

    // MARK: - Update

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update annotations if cities changed
        let existingCities = Set(
            mapView.annotations.compactMap { ($0 as? CityAnnotation)?.city.name }
        )
        let newCities = Set(cities.map(\.name))

        if existingCities != newCities {
            let toRemove = mapView.annotations.filter { $0 is CityAnnotation }
            mapView.removeAnnotations(toRemove)
            let annotations = cities.map { CityAnnotation(city: $0) }
            mapView.addAnnotations(annotations)
        }

        // Animate to selected city
        if let city = selectedCity,
           context.coordinator.lastSelectedCityName != city.name {
            context.coordinator.lastSelectedCityName = city.name
            let camera = MKMapCamera(
                lookingAtCenter: city.coordinate,
                fromDistance: 500_000,
                pitch: 45,
                heading: 0
            )
            UIView.animate(withDuration: 1.2) {
                mapView.camera = camera
            }
        }

        // Handle zoom button changes
        let currentMapDistance = mapView.camera.centerCoordinateDistance
        let distanceDelta = abs(currentMapDistance - cameraDistance) / max(currentMapDistance, 1)
        if distanceDelta > 0.1 && context.coordinator.lastSelectedCityName == selectedCity?.name {
            let camera = MKMapCamera(
                lookingAtCenter: mapView.camera.centerCoordinate,
                fromDistance: cameraDistance,
                pitch: cameraDistance < 100_000 ? 60 : 0,
                heading: mapView.camera.heading
            )
            UIView.animate(withDuration: 0.5) {
                mapView.camera = camera
            }
        }
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ClusterMapView
        var lastSelectedCityName: String?

        init(parent: ClusterMapView) {
            self.parent = parent
        }

        // MARK: Annotation Views

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: annotation
                )
            }
            if annotation is CityAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
                    for: annotation
                )
            }
            return nil
        }

        // MARK: Annotation Selection

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)

            if let cluster = annotation as? MKClusterAnnotation {
                // Tap on cluster → zoom into the cluster region (Req 3.4)
                let memberAnnotations = cluster.memberAnnotations
                mapView.showAnnotations(memberAnnotations, animated: true)
                return
            }

            if let cityAnnotation = annotation as? CityAnnotation {
                let feedback = UIImpactFeedbackGenerator(style: .medium)
                feedback.impactOccurred()
                DispatchQueue.main.async {
                    self.parent.selectedCity = cityAnnotation.city
                }
            }
        }

        // MARK: Camera Changes — track distance

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.cameraDistance = mapView.camera.centerCoordinateDistance
            }
        }
    }
}


// MARK: - CityAnnotationView (Individual Marker)

/// Custom annotation view for individual city markers with the app's design language.
/// Shows a cyan dot with city name label. Supports clustering via `clusteringIdentifier`.
final class CityAnnotationView: MKAnnotationView {

    static let clusterID = "cityCluster"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = Self.clusterID
        collisionMode = .circle
        setupView()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    // MARK: - Setup

    private let dotView = UIView()
    private let innerDot = UIView()
    private let centerDot = UIView()
    private let nameLabel = UILabel()
    private let labelBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 80, height: 60)
        centerOffset = CGPoint(x: 0, y: -30)
        backgroundColor = .clear

        // Outer glow
        dotView.frame = CGRect(x: 26, y: 0, width: 28, height: 28)
        dotView.backgroundColor = UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 0.3)
        dotView.layer.cornerRadius = 14
        addSubview(dotView)

        // Inner dot
        innerDot.frame = CGRect(x: 33, y: 7, width: 14, height: 14)
        innerDot.backgroundColor = UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 1)
        innerDot.layer.cornerRadius = 7
        addSubview(innerDot)

        // Center white dot
        centerDot.frame = CGRect(x: 37, y: 11, width: 6, height: 6)
        centerDot.backgroundColor = .white
        centerDot.layer.cornerRadius = 3
        addSubview(centerDot)

        // Name label with blur background
        labelBackground.frame = CGRect(x: 0, y: 32, width: 80, height: 22)
        labelBackground.layer.cornerRadius = 11
        labelBackground.clipsToBounds = true
        addSubview(labelBackground)

        nameLabel.frame = labelBackground.bounds
        nameLabel.textAlignment = .center
        nameLabel.font = .systemFont(ofSize: 10, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        labelBackground.contentView.addSubview(nameLabel)

        configure()
    }

    private func configure() {
        guard let cityAnnotation = annotation as? CityAnnotation else { return }
        nameLabel.text = cityAnnotation.city.name

        // Size label to fit city name
        let textWidth = (cityAnnotation.city.name as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold)]
        ).width
        let labelWidth = max(40, min(textWidth + 16, 120))
        let labelX = (80 - labelWidth) / 2
        labelBackground.frame = CGRect(x: labelX, y: 32, width: labelWidth, height: 22)
        nameLabel.frame = labelBackground.bounds
    }
}

// MARK: - ClusterAnnotationView (Grouped Markers)

/// Custom annotation view for clustered city markers showing a count badge.
/// Validates: Requirements 3.1, 3.3
final class ClusterAnnotationView: MKAnnotationView {

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        setupView()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    // MARK: - Setup

    private let circleView = UIView()
    private let countLabel = UILabel()

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        centerOffset = CGPoint(x: 0, y: -24)
        backgroundColor = .clear

        // Outer circle with gradient-like appearance
        circleView.frame = bounds
        circleView.layer.cornerRadius = 24
        circleView.clipsToBounds = true
        circleView.layer.borderWidth = 2
        circleView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor

        // Gradient background
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = circleView.bounds
        gradientLayer.colors = [
            UIColor(red: 0, green: 0.85, blue: 0.95, alpha: 0.9).cgColor,
            UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 0.9).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        circleView.layer.insertSublayer(gradientLayer, at: 0)
        addSubview(circleView)

        // Count label
        countLabel.frame = circleView.bounds
        countLabel.textAlignment = .center
        countLabel.font = .systemFont(ofSize: 16, weight: .bold)
        countLabel.textColor = .white
        circleView.addSubview(countLabel)

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6

        configure()
    }

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count
        countLabel.text = "\(count)"

        // Scale circle size based on count
        let size: CGFloat = count > 10 ? 56 : (count > 5 ? 52 : 48)
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = CGPoint(x: 0, y: -size / 2)
        circleView.frame = bounds
        circleView.layer.cornerRadius = size / 2
        countLabel.frame = circleView.bounds

        // Update gradient layer frame
        if let gradientLayer = circleView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = circleView.bounds
        }
    }
}
