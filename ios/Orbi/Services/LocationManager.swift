import Foundation
import CoreLocation

// MARK: - LocationManager

/// CLLocationManager wrapper providing GPS location with UserDefaults persistence and fallback chain.
/// Fallback: GPS → UserDefaults → New York default (40.7128, -74.0060).
/// Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    static let defaultLocation = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    private let manager = CLLocationManager()
    private let latKey = "lastKnownLatitude"
    private let lngKey = "lastKnownLongitude"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus

        // Initialize with fallback chain
        if let saved = loadLastKnown() {
            currentLocation = saved
        } else {
            currentLocation = Self.defaultLocation
        }
    }

    // MARK: - Public

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            // Permission denied — use fallback
            if currentLocation == nil {
                currentLocation = loadLastKnown() ?? Self.defaultLocation
            }
        }
    }

    func persistLastKnown(_ coordinate: CLLocationCoordinate2D) {
        UserDefaults.standard.set(coordinate.latitude, forKey: latKey)
        UserDefaults.standard.set(coordinate.longitude, forKey: lngKey)
    }

    func loadLastKnown() -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latKey) != nil else { return nil }
        let lat = defaults.double(forKey: latKey)
        let lng = defaults.double(forKey: lngKey)
        guard lat >= -90, lat <= 90, lng >= -180, lng <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coord = location.coordinate
        Task { @MainActor in
            self.currentLocation = coord
            self.persistLastKnown(coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep existing fallback location
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
}
