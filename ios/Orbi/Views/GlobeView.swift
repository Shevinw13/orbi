import SwiftUI
import SceneKit

// MARK: - CityMarker

/// Represents a city marker on the globe with geographic coordinates.
/// Validates: Requirement 1.4
struct CityMarker: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double

    static func == (lhs: CityMarker, rhs: CityMarker) -> Bool {
        lhs.id == rhs.id
    }

    /// Popular cities displayed as markers on the globe.
    static let popularCities: [CityMarker] = [
        CityMarker(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        CityMarker(name: "Paris", latitude: 48.8566, longitude: 2.3522),
        CityMarker(name: "New York", latitude: 40.7128, longitude: -74.0060),
        CityMarker(name: "London", latitude: 51.5074, longitude: -0.1278),
        CityMarker(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
        CityMarker(name: "Dubai", latitude: 25.2048, longitude: 55.2708),
        CityMarker(name: "Rome", latitude: 41.9028, longitude: 12.4964),
        CityMarker(name: "Barcelona", latitude: 41.3874, longitude: 2.1686),
    ]
}

// MARK: - Coordinate Conversion

/// Converts latitude/longitude (degrees) to a 3D position on a sphere surface.
/// - Parameters:
///   - lat: Latitude in degrees (-90 to 90).
///   - lng: Longitude in degrees (-180 to 180).
///   - radius: Sphere radius.
/// - Returns: `SCNVector3` position on the sphere.
/// Validates: Requirement 1.4
func latLngToPosition(lat: Double, lng: Double, radius: Double) -> SCNVector3 {
    let latRad = lat * .pi / 180.0
    let lngRad = lng * .pi / 180.0

    let x = radius * cos(latRad) * sin(lngRad)
    let y = radius * sin(latRad)
    let z = radius * cos(latRad) * cos(lngRad)

    return SCNVector3(Float(x), Float(y), Float(z))
}

// MARK: - GlobeView

/// A 3D interactive globe rendered via SceneKit, wrapped for SwiftUI.
/// Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 15.1
struct GlobeView: UIViewRepresentable {

    /// Binding so the parent view knows which city was tapped.
    /// Validates: Requirement 1.4
    @Binding var selectedCity: CityMarker?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedCity: $selectedCity)
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = GlobeScene.create()
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = false

        // Store scene reference in coordinator for gesture handlers
        context.coordinator.sceneView = sceneView

        // Add city markers to the earth node (Requirement 1.4)
        if let earthNode = sceneView.scene?.rootNode.childNode(withName: "earth", recursively: false) {
            context.coordinator.addCityMarkers(to: earthNode)
        }

        // Pan gesture → rotate globe (Requirement 1.2)
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        sceneView.addGestureRecognizer(panGesture)

        // Pinch gesture → zoom camera (Requirement 1.3)
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        sceneView.addGestureRecognizer(pinchGesture)

        // Tap gesture → detect city marker taps (Requirement 1.4)
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        sceneView.addGestureRecognizer(tapGesture)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // When selectedCity is set externally (e.g. from search bar), animate the globe.
        // Requirement 2.3: On search selection, animate globe to selected city.
        if let city = selectedCity,
           city != context.coordinator.lastAnimatedCity {
            context.coordinator.lastAnimatedCity = city
            context.coordinator.animateToCity(city)
        }
    }

    // MARK: - Coordinator

    /// Gesture handler for the globe view.
    /// Manages pan-to-rotate, pinch-to-zoom, tap-to-select, and animation lock state.
    /// Validates: Requirements 1.2, 1.3, 1.4, 1.5
    class Coordinator: NSObject {

        weak var sceneView: SCNView?

        /// Binding to communicate tapped city back to the parent view.
        var selectedCity: Binding<CityMarker?>

        /// Maps marker node names to their `CityMarker` data.
        private var markerMap: [String: CityMarker] = [:]

        /// Tracks the last city animated to, preventing duplicate animations from updateUIView.
        var lastAnimatedCity: CityMarker?

        /// When `true`, tap interactions are disabled (zoom transition in progress).
        /// Validates: Requirement 1.5
        private(set) var isAnimating: Bool = false

        /// Sensitivity multiplier for pan-to-rotation mapping.
        private let panSensitivity: Float = 0.005

        /// Camera Z-position limits for pinch zoom.
        static let minZoom: Float = 1.8
        static let maxZoom: Float = 8.0

        /// Duration (seconds) for animated zoom transitions.
        private let zoomAnimationDuration: TimeInterval = 0.3

        /// Duration (seconds) for the city-tap zoom animation.
        /// Validates: Requirement 1.4
        private let cityZoomDuration: TimeInterval = 1.0

        /// Camera distance when zoomed into a city.
        private let cityZoomDistance: Float = 2.0

        /// Marker node name prefix for hit-test identification.
        static let markerPrefix = "cityMarker_"

        init(selectedCity: Binding<CityMarker?>) {
            self.selectedCity = selectedCity
        }

        // MARK: - City Markers (Requirement 1.4)

        /// Creates and attaches small sphere markers for each popular city on the earth node.
        func addCityMarkers(to earthNode: SCNNode) {
            let markerRadius: CGFloat = 0.04
            let markerColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0) // bright orange

            for city in CityMarker.popularCities {
                // Glowing marker sphere
                let sphere = SCNSphere(radius: markerRadius)
                let material = SCNMaterial()
                material.diffuse.contents = markerColor
                material.emission.contents = markerColor
                sphere.firstMaterial = material

                let markerNode = SCNNode(geometry: sphere)
                let nodeName = "\(Coordinator.markerPrefix)\(city.name)"
                markerNode.name = nodeName
                markerNode.position = latLngToPosition(
                    lat: city.latitude,
                    lng: city.longitude,
                    radius: Double(GlobeScene.earthRadius) + Double(markerRadius)
                )

                // Add a pulsing outer ring for visibility
                let ring = SCNTorus(ringRadius: markerRadius * 2.0, pipeRadius: markerRadius * 0.3)
                let ringMaterial = SCNMaterial()
                ringMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.6)
                ringMaterial.emission.contents = UIColor.white.withAlphaComponent(0.4)
                ring.firstMaterial = ringMaterial
                let ringNode = SCNNode(geometry: ring)
                ringNode.eulerAngles.x = .pi / 2
                markerNode.addChildNode(ringNode)

                // Add city name label
                let text = SCNText(string: city.name, extrusionDepth: 0.002)
                text.font = UIFont.systemFont(ofSize: 0.06, weight: .bold)
                text.firstMaterial?.diffuse.contents = UIColor.white
                text.firstMaterial?.emission.contents = UIColor.white
                text.flatness = 0.1
                let textNode = SCNNode(geometry: text)
                textNode.scale = SCNVector3(0.5, 0.5, 0.5)
                // Center the text above the marker
                let (minBound, maxBound) = textNode.boundingBox
                let textWidth = (maxBound.x - minBound.x) * 0.5
                textNode.position = SCNVector3(-textWidth / 2, Float(markerRadius) * 2.5, 0)
                // Make text always face camera
                textNode.constraints = [SCNBillboardConstraint()]
                markerNode.addChildNode(textNode)

                markerMap[nodeName] = city
                earthNode.addChildNode(markerNode)
            }
        }

        // MARK: - Tap Gesture (Requirement 1.4)

        /// Handles tap on the scene view. Performs a hit test to detect city markers.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard !isAnimating,
                  let sceneView = sceneView else { return }

            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])

            // Find the first hit that matches a city marker
            for result in hitResults {
                if let nodeName = result.node.name,
                   nodeName.hasPrefix(Coordinator.markerPrefix),
                   let city = markerMap[nodeName] {
                    animateZoomToCity(city)
                    return
                }
            }
        }

        // MARK: - Zoom to City (Requirement 1.4)

        /// Public entry point for animating to a city (called from updateUIView for search selection).
        /// Validates: Requirement 2.3
        func animateToCity(_ city: CityMarker) {
            animateZoomToCity(city)
        }

        /// Animates the camera to zoom into the tapped city's location.
        private func animateZoomToCity(_ city: CityMarker) {
            guard let sceneView = sceneView,
                  let cameraNode = sceneView.scene?.rootNode.childNodes.first(
                      where: { $0.camera != nil }
                  ),
                  let earthNode = sceneView.scene?.rootNode.childNode(
                      withName: "earth", recursively: false
                  ) else { return }

            setAnimating(true)

            // Compute target position on the sphere surface at zoom distance
            let targetPos = latLngToPosition(
                lat: city.latitude,
                lng: city.longitude,
                radius: Double(cityZoomDistance)
            )

            SCNTransaction.begin()
            SCNTransaction.animationDuration = cityZoomDuration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            SCNTransaction.completionBlock = { [weak self] in
                self?.setAnimating(false)
                // Notify parent view of the selected city
                DispatchQueue.main.async {
                    self?.selectedCity.wrappedValue = city
                }
            }

            // Reset earth rotation so the city faces the camera
            earthNode.eulerAngles = SCNVector3(0, 0, 0)

            // Move camera to face the city
            cameraNode.position = targetPos

            SCNTransaction.commit()
        }

        // MARK: - Pan Gesture (Requirement 1.2)

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView = sceneView,
                  let earthNode = sceneView.scene?.rootNode.childNode(
                      withName: "earth", recursively: false
                  ) else { return }

            let translation = gesture.translation(in: sceneView)

            // Map horizontal pan → Y-axis rotation, vertical pan → X-axis rotation
            earthNode.eulerAngles.y += Float(translation.x) * panSensitivity
            earthNode.eulerAngles.x += Float(translation.y) * panSensitivity

            // Reset translation so deltas stay incremental
            gesture.setTranslation(.zero, in: sceneView)
        }

        // MARK: - Pinch Gesture (Requirement 1.3)

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let sceneView = sceneView,
                  let cameraNode = sceneView.scene?.rootNode.childNodes.first(
                      where: { $0.camera != nil }
                  ) else { return }

            switch gesture.state {
            case .began:
                setAnimating(true)

            case .changed:
                // Scale factor > 1 means pinch-out (zoom in → move camera closer)
                let currentZ = cameraNode.position.z
                let delta = Float(1.0 / gesture.scale) - 1.0
                let newZ = (currentZ + currentZ * delta)
                    .clamped(to: Coordinator.minZoom...Coordinator.maxZoom)

                SCNTransaction.begin()
                SCNTransaction.animationDuration = zoomAnimationDuration
                cameraNode.position.z = newZ
                SCNTransaction.commit()

                // Reset scale so deltas stay incremental
                gesture.scale = 1.0

            case .ended, .cancelled:
                // Unlock taps after a brief settle period
                SCNTransaction.begin()
                SCNTransaction.animationDuration = zoomAnimationDuration
                SCNTransaction.completionBlock = { [weak self] in
                    self?.setAnimating(false)
                }
                SCNTransaction.commit()

            default:
                break
            }
        }

        // MARK: - Animation Lock (Requirement 1.5)

        /// Sets the animation lock flag. While animating, tap interactions should be ignored.
        func setAnimating(_ value: Bool) {
            isAnimating = value
        }
    }
}

// MARK: - Float Clamping

private extension Float {
    /// Clamps the value to the given closed range.
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - GlobeScene

/// Factory that builds the SceneKit scene: Earth sphere, lights, and camera.
enum GlobeScene {

    /// Sphere radius used for the Earth node.
    static let earthRadius: CGFloat = 1.0

    /// Distance from the origin where the camera is placed.
    static let cameraDistance: Float = 3.5

    static func create() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.02, green: 0.02, blue: 0.08, alpha: 1.0)

        // Earth
        let earthNode = makeEarth()
        earthNode.name = "earth"
        scene.rootNode.addChildNode(earthNode)

        // Atmosphere glow
        let atmosphere = makeAtmosphere()
        scene.rootNode.addChildNode(atmosphere)

        // Lighting
        scene.rootNode.addChildNode(makeAmbientLight())
        scene.rootNode.addChildNode(makeDirectionalLight())

        // Camera
        scene.rootNode.addChildNode(makeCamera())

        return scene
    }

    // MARK: - Earth

    private static func makeEarth() -> SCNNode {
        let sphere = SCNSphere(radius: earthRadius)
        sphere.segmentCount = 96

        let material = SCNMaterial()
        if let texture = UIImage(named: "earth_texture") {
            material.diffuse.contents = texture
        } else {
            // Nice gradient-like ocean color without texture
            material.diffuse.contents = UIColor(red: 0.12, green: 0.30, blue: 0.55, alpha: 1.0)
        }
        material.specular.contents = UIColor(white: 0.3, alpha: 1.0)
        material.shininess = 0.2
        material.locksAmbientWithDiffuse = true
        material.isDoubleSided = false
        sphere.firstMaterial = material

        return SCNNode(geometry: sphere)
    }

    // MARK: - Atmosphere

    private static func makeAtmosphere() -> SCNNode {
        let sphere = SCNSphere(radius: earthRadius * 1.03)
        sphere.segmentCount = 64
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.08)
        material.emission.contents = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.15)
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        sphere.firstMaterial = material
        return SCNNode(geometry: sphere)
    }

    // MARK: - Lighting

    private static func makeAmbientLight() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 400
        light.color = UIColor.white

        let node = SCNNode()
        node.light = light
        return node
    }

    private static func makeDirectionalLight() -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = 800
        light.color = UIColor.white
        light.castsShadow = false

        let node = SCNNode()
        node.light = light
        node.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        return node
    }

    // MARK: - Camera

    private static func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.zNear = 0.1
        camera.zFar = 100

        let node = SCNNode()
        node.camera = camera
        node.position = SCNVector3(0, 0, cameraDistance)

        // Look at the origin (center of the globe)
        let constraint = SCNLookAtConstraint(target: nil)
        constraint.isGimbalLockEnabled = true
        node.constraints = [constraint]

        return node
    }
}

// MARK: - Preview

#Preview {
    GlobeView(selectedCity: .constant(nil))
        .ignoresSafeArea()
}
