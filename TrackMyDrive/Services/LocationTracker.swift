import Foundation
import CoreLocation

/// Wraps CLLocationManager for drive tracking. Updates continue with the screen locked
/// (blue status-bar pill) because the app declares the `location` background mode.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    static let shared = LocationTracker()

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var isTracking = false
    /// False when the user turned off Precise Location; fixes are then too rough to measure distance.
    @Published private(set) var isPrecise = true

    var onLocation: (@MainActor (CLLocation) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }

    /// Asks for precise location for this drive only (iOS shows a one-time prompt).
    func requestPreciseLocation() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "DriveDistance") { [weak self] _ in
            Task { @MainActor in self?.refreshAccuracy() }
        }
    }

    private func refreshAccuracy() {
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Current speed in m/s, or nil when unknown or stale.
    var currentSpeed: Double? {
        guard isTracking, let loc = lastLocation, loc.speed >= 0,
              abs(loc.timestamp.timeIntervalSinceNow) < 10 else { return nil }
        return loc.speed
    }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func start() {
        isTracking = true
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return // updates begin once permission is granted
        }
        beginUpdatesIfAllowed()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func beginUpdatesIfAllowed() {
        guard isTracking, isAuthorized else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    fileprivate func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorization = status
        refreshAccuracy()
        beginUpdatesIfAllowed()
    }

    fileprivate func handle(_ locations: [CLLocation]) {
        guard isTracking else { return }
        for location in locations {
            lastLocation = location
            onLocation?(location)
        }
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.handleAuthorizationChange(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.handle(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient errors (e.g. no fix in a tunnel) are expected; CoreLocation keeps trying.
    }
}
