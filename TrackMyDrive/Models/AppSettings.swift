import Foundation

enum NightMode: String, Codable, CaseIterable, Identifiable {
    /// Night is sunset to sunrise at the drive's location (most US states).
    case sunsetToSunrise
    /// Night is a fixed clock window, e.g. 9:00 PM – 5:00 AM.
    case fixedHours
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sunsetToSunrise: return "Sunset to Sunrise"
        case .fixedHours: return "Fixed Hours"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case miles, kilometers
    var id: String { rawValue }
    var label: String { self == .miles ? "Miles" : "Kilometers" }
    var abbreviation: String { self == .miles ? "mi" : "km" }
    var metersPerUnit: Double { self == .miles ? 1609.344 : 1000 }
    var speedLabel: String { self == .miles ? "mph" : "km/h" }
    func value(fromMeters m: Double) -> Double { m / metersPerUnit }
    func meters(from value: Double) -> Double { value * metersPerUnit }
}

struct AppSettings: Codable, Equatable {
    var studentName: String = ""
    var permitNumber: String = ""
    var stateCode: String = ""
    var totalGoalHours: Double = 50
    var nightGoalHours: Double = 10
    /// Bad-weather hours required (0 = no requirement).
    var weatherGoalHours: Double = 0
    /// When the learner's permit was issued, and how long it must be held before the road test.
    var permitIssued: Date?
    var minPermitMonths: Int = 0
    /// The driver whose name, permit and goals are in the fields above; drives are tagged with this id.
    var activeDriverID = UUID()
    /// Every other driver's profile (siblings sharing the app).
    var otherDrivers: [DriverProfile] = []
    var nightMode: NightMode = .sunsetToSunrise
    /// Minutes after sunset (and before sunrise) before driving counts as night. Some states use 30.
    var nightOffsetMinutes: Int = 0
    /// Minutes after midnight.
    var fixedNightStartMinutes: Int = 21 * 60
    var fixedNightEndMinutes: Int = 5 * 60
    var defaultSupervisor: String = ""
    var supervisors: [String] = []
    var defaultVehicle: String = ""
    var vehicles: [String] = []
    var distanceUnit: DistanceUnit = .miles
    var trackLocation: Bool = true
    var keepScreenOnWhileDriving: Bool = false
    var reminderEnabled: Bool = false
    var reminderMinutes: Int = 17 * 60
    var hasOnboarded: Bool = false
    var lastKnownLatitude: Double?
    var lastKnownLongitude: Double?
    var lastExternalBackup: Date?
    var lastNotesBackup: Date?

    static let `default` = AppSettings()

    init() {}

    // Tolerant decoding: any missing key falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        studentName = (try? c.decodeIfPresent(String.self, forKey: .studentName)) ?? d.studentName
        permitNumber = (try? c.decodeIfPresent(String.self, forKey: .permitNumber)) ?? d.permitNumber
        stateCode = (try? c.decodeIfPresent(String.self, forKey: .stateCode)) ?? d.stateCode
        totalGoalHours = (try? c.decodeIfPresent(Double.self, forKey: .totalGoalHours)) ?? d.totalGoalHours
        nightGoalHours = (try? c.decodeIfPresent(Double.self, forKey: .nightGoalHours)) ?? d.nightGoalHours
        nightMode = (try? c.decodeIfPresent(NightMode.self, forKey: .nightMode)) ?? d.nightMode
        nightOffsetMinutes = (try? c.decodeIfPresent(Int.self, forKey: .nightOffsetMinutes)) ?? d.nightOffsetMinutes
        fixedNightStartMinutes = (try? c.decodeIfPresent(Int.self, forKey: .fixedNightStartMinutes)) ?? d.fixedNightStartMinutes
        fixedNightEndMinutes = (try? c.decodeIfPresent(Int.self, forKey: .fixedNightEndMinutes)) ?? d.fixedNightEndMinutes
        defaultSupervisor = (try? c.decodeIfPresent(String.self, forKey: .defaultSupervisor)) ?? d.defaultSupervisor
        supervisors = (try? c.decodeIfPresent([String].self, forKey: .supervisors)) ?? d.supervisors
        defaultVehicle = (try? c.decodeIfPresent(String.self, forKey: .defaultVehicle)) ?? d.defaultVehicle
        vehicles = (try? c.decodeIfPresent([String].self, forKey: .vehicles)) ?? d.vehicles
        distanceUnit = (try? c.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit)) ?? d.distanceUnit
        trackLocation = (try? c.decodeIfPresent(Bool.self, forKey: .trackLocation)) ?? d.trackLocation
        keepScreenOnWhileDriving = (try? c.decodeIfPresent(Bool.self, forKey: .keepScreenOnWhileDriving)) ?? d.keepScreenOnWhileDriving
        reminderEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .reminderEnabled)) ?? d.reminderEnabled
        reminderMinutes = (try? c.decodeIfPresent(Int.self, forKey: .reminderMinutes)) ?? d.reminderMinutes
        hasOnboarded = (try? c.decodeIfPresent(Bool.self, forKey: .hasOnboarded)) ?? d.hasOnboarded
        weatherGoalHours = (try? c.decodeIfPresent(Double.self, forKey: .weatherGoalHours)) ?? d.weatherGoalHours
        permitIssued = try? c.decodeIfPresent(Date.self, forKey: .permitIssued)
        minPermitMonths = (try? c.decodeIfPresent(Int.self, forKey: .minPermitMonths)) ?? d.minPermitMonths
        activeDriverID = (try? c.decodeIfPresent(UUID.self, forKey: .activeDriverID)) ?? d.activeDriverID
        otherDrivers = (try? c.decodeIfPresent([DriverProfile].self, forKey: .otherDrivers)) ?? d.otherDrivers
        lastKnownLatitude = try? c.decodeIfPresent(Double.self, forKey: .lastKnownLatitude)
        lastKnownLongitude = try? c.decodeIfPresent(Double.self, forKey: .lastKnownLongitude)
        lastExternalBackup = try? c.decodeIfPresent(Date.self, forKey: .lastExternalBackup)
        lastNotesBackup = try? c.decodeIfPresent(Date.self, forKey: .lastNotesBackup)
    }

    var totalGoalMinutes: Double { max(0, totalGoalHours) * 60 }
    var nightGoalMinutes: Double { max(0, nightGoalHours) * 60 }
    var weatherGoalMinutes: Double { max(0, weatherGoalHours) * 60 }

    /// Earliest road-test date allowed by the permit holding period, if known.
    var earliestTestDate: Date? {
        guard let permitIssued, minPermitMonths > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: minPermitMonths, to: permitIssued)
    }

    /// The active driver's profile, read from / written to the fields above.
    var activeProfile: DriverProfile {
        get {
            DriverProfile(id: activeDriverID, name: studentName, permitNumber: permitNumber, stateCode: stateCode,
                          totalGoalHours: totalGoalHours, nightGoalHours: nightGoalHours, weatherGoalHours: weatherGoalHours,
                          permitIssued: permitIssued, minPermitMonths: minPermitMonths)
        }
        set {
            activeDriverID = newValue.id
            studentName = newValue.name
            permitNumber = newValue.permitNumber
            stateCode = newValue.stateCode
            totalGoalHours = newValue.totalGoalHours
            nightGoalHours = newValue.nightGoalHours
            weatherGoalHours = newValue.weatherGoalHours
            permitIssued = newValue.permitIssued
            minPermitMonths = newValue.minPermitMonths
        }
    }

    /// All drivers, active first.
    var allDrivers: [DriverProfile] { [activeProfile] + otherDrivers }

    /// These settings as seen by another driver (their goals and name), for stats and exports.
    func viewed(as profile: DriverProfile) -> AppSettings {
        var s = self
        s.activeProfile = profile
        return s
    }

    var statePreset: StatePreset? { StatePreset.all.first { $0.code == stateCode } }

    /// Names offered in pickers: saved supervisors, with the default first.
    var supervisorOptions: [String] {
        var list = supervisors
        if !defaultSupervisor.isEmpty, !list.contains(defaultSupervisor) { list.insert(defaultSupervisor, at: 0) }
        return list
    }

    var vehicleOptions: [String] {
        var list = vehicles
        if !defaultVehicle.isEmpty, !list.contains(defaultVehicle) { list.insert(defaultVehicle, at: 0) }
        return list
    }
}

/// One learner driver. The active driver's profile lives in AppSettings' own fields.
struct DriverProfile: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var permitNumber = ""
    var stateCode = ""
    var totalGoalHours: Double = 50
    var nightGoalHours: Double = 10
    var weatherGoalHours: Double = 0
    var permitIssued: Date?
    var minPermitMonths: Int = 0

    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Driver" : name }
}
