import Foundation

/// The drive currently being timed. Persisted to disk on every meaningful change so the timer
/// survives the app being closed, crashing, or the phone restarting.
struct ActiveDrive: Codable, Equatable {
    var id: UUID = UUID()
    var startDate: Date
    /// Set when the user taps Stop; the drive waits here until they save or discard it.
    var stoppedAt: Date?
    var supervisor: String
    var vehicle: String
    var distanceMeters: Double = 0
    var route: [RoutePoint] = []
    var startLatitude: Double?
    var startLongitude: Double?
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastFixDate: Date?
    var startPlaceName: String?
    var endPlaceName: String?
    var maxSpeedMetersPerSecond: Double = 0
    var timeZoneIdentifier: String? = TimeZone.current.identifier

    init(startDate: Date, supervisor: String, vehicle: String) {
        self.startDate = startDate
        self.supervisor = supervisor
        self.vehicle = vehicle
    }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, (stoppedAt ?? now).timeIntervalSince(startDate))
    }
}
