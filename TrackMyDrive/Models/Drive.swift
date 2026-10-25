import Foundation

/// A single logged practice drive.
struct Drive: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startDate: Date
    var endDate: Date
    /// Minutes of this drive that count as night driving.
    var nightMinutes: Double = 0
    /// True when the user typed the night minutes in by hand, so automatic recalculation leaves them alone.
    var nightMinutesIsManual: Bool = false
    var supervisor: String = ""
    var vehicle: String = ""
    var distanceMeters: Double?
    var weather: Set<WeatherCondition> = []
    var roads: Set<RoadType> = []
    var skills: Set<DrivingSkill> = []
    var notes: String = ""
    var source: DriveSource = .manual
    var startLatitude: Double?
    var startLongitude: Double?
    var startPlaceName: String?
    var endPlaceName: String?
    var route: [RoutePoint] = []
    /// Where the drive happened, so night time is always worked out in the drive's own time zone.
    var timeZoneIdentifier: String? = TimeZone.current.identifier
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
    var totalMinutes: Double { duration / 60 }
    var clampedNightMinutes: Double { min(max(0, nightMinutes), totalMinutes) }
    var dayMinutes: Double { totalMinutes - clampedNightMinutes }
    var isMostlyNight: Bool { clampedNightMinutes > totalMinutes / 2 }

    var averageSpeedMetersPerSecond: Double? {
        guard let distanceMeters, duration > 60 else { return nil }
        return distanceMeters / duration
    }

    /// A calendar in the drive's own time zone (falls back to the phone's).
    var calendar: Calendar {
        var c = Calendar.current
        if let id = timeZoneIdentifier, let tz = TimeZone(identifier: id) { c.timeZone = tz }
        return c
    }

    var routeSummary: String? {
        switch (startPlaceName, endPlaceName) {
        case (let s?, let e?) where s != e: return "\(s) → \(e)"
        case (let s?, _): return s
        case (nil, let e?): return e
        case (nil, nil): return nil
        }
    }

    // MARK: Codable (tolerant decoding so old or hand-edited backups always restore)

    enum CodingKeys: String, CodingKey {
        case id, startDate, endDate, nightMinutes, nightMinutesIsManual, supervisor, vehicle,
             distanceMeters, weather, roads, skills, notes, source, startLatitude, startLongitude,
             startPlaceName, endPlaceName, route, timeZoneIdentifier, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        nightMinutes = try c.decodeIfPresent(Double.self, forKey: .nightMinutes) ?? 0
        nightMinutesIsManual = try c.decodeIfPresent(Bool.self, forKey: .nightMinutesIsManual) ?? false
        supervisor = try c.decodeIfPresent(String.self, forKey: .supervisor) ?? ""
        vehicle = try c.decodeIfPresent(String.self, forKey: .vehicle) ?? ""
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters)
        weather = Set((try c.decodeIfPresent([String].self, forKey: .weather) ?? []).compactMap(WeatherCondition.init(rawValue:)))
        roads = Set((try c.decodeIfPresent([String].self, forKey: .roads) ?? []).compactMap(RoadType.init(rawValue:)))
        skills = Set((try c.decodeIfPresent([String].self, forKey: .skills) ?? []).compactMap(DrivingSkill.init(rawValue:)))
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        source = DriveSource(rawValue: (try c.decodeIfPresent(String.self, forKey: .source)) ?? "") ?? .manual
        startLatitude = try c.decodeIfPresent(Double.self, forKey: .startLatitude)
        startLongitude = try c.decodeIfPresent(Double.self, forKey: .startLongitude)
        startPlaceName = try c.decodeIfPresent(String.self, forKey: .startPlaceName)
        endPlaceName = try c.decodeIfPresent(String.self, forKey: .endPlaceName)
        route = (try? c.decodeIfPresent([RoutePoint].self, forKey: .route)) ?? []
        // Older drives don't have one; nil means "use the phone's time zone".
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? startDate
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encode(nightMinutes, forKey: .nightMinutes)
        try c.encode(nightMinutesIsManual, forKey: .nightMinutesIsManual)
        try c.encode(supervisor, forKey: .supervisor)
        try c.encode(vehicle, forKey: .vehicle)
        try c.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try c.encode(weather.map(\.rawValue).sorted(), forKey: .weather)
        try c.encode(roads.map(\.rawValue).sorted(), forKey: .roads)
        try c.encode(skills.map(\.rawValue).sorted(), forKey: .skills)
        try c.encode(notes, forKey: .notes)
        try c.encode(source.rawValue, forKey: .source)
        try c.encodeIfPresent(startLatitude, forKey: .startLatitude)
        try c.encodeIfPresent(startLongitude, forKey: .startLongitude)
        try c.encodeIfPresent(startPlaceName, forKey: .startPlaceName)
        try c.encodeIfPresent(endPlaceName, forKey: .endPlaceName)
        if !route.isEmpty { try c.encode(route, forKey: .route) }
        try c.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }
}

struct RoutePoint: Codable, Hashable {
    var lat: Double
    var lon: Double
}

enum DriveSource: String, Codable {
    case tracked, manual
}

/// A drive the user deleted; kept for 30 days so mistakes can be undone.
struct DeletedDrive: Identifiable, Codable, Hashable {
    var drive: Drive
    var deletedAt: Date
    var id: UUID { drive.id }
}

enum WeatherCondition: String, Codable, CaseIterable, Identifiable {
    case clear, cloudy, rain, fog, snow, ice, wind
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .rain: return "Rain"
        case .fog: return "Fog"
        case .snow: return "Snow"
        case .ice: return "Ice"
        case .wind: return "Windy"
        }
    }
    var symbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .fog: return "cloud.fog.fill"
        case .snow: return "cloud.snow.fill"
        case .ice: return "snowflake"
        case .wind: return "wind"
        }
    }
    /// Conditions most DMVs count as "adverse weather".
    var isAdverse: Bool { self != .clear && self != .cloudy }
}

enum RoadType: String, Codable, CaseIterable, Identifiable {
    case residential, city, highway, rural, parkingLot, construction
    var id: String { rawValue }
    var label: String {
        switch self {
        case .residential: return "Residential"
        case .city: return "City"
        case .highway: return "Highway"
        case .rural: return "Rural"
        case .parkingLot: return "Parking Lot"
        case .construction: return "Construction"
        }
    }
    var symbol: String {
        switch self {
        case .residential: return "house.fill"
        case .city: return "building.2.fill"
        case .highway: return "road.lanes"
        case .rural: return "tree.fill"
        case .parkingLot: return "parkingsign"
        case .construction: return "cone.fill"
        }
    }
}

enum DrivingSkill: String, Codable, CaseIterable, Identifiable {
    case parallelParking, perpendicularParking, threePointTurn, laneChanges, merging,
         roundabouts, intersections, backingUp, hills, heavyTraffic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .parallelParking: return "Parallel Parking"
        case .perpendicularParking: return "Parking Spaces"
        case .threePointTurn: return "3-Point Turn"
        case .laneChanges: return "Lane Changes"
        case .merging: return "Merging"
        case .roundabouts: return "Roundabouts"
        case .intersections: return "Intersections"
        case .backingUp: return "Backing Up"
        case .hills: return "Hills"
        case .heavyTraffic: return "Heavy Traffic"
        }
    }
    var symbol: String {
        switch self {
        case .parallelParking: return "parkingsign.circle.fill"
        case .perpendicularParking: return "car.rear.fill"
        case .threePointTurn: return "arrow.uturn.backward"
        case .laneChanges: return "arrow.left.arrow.right"
        case .merging: return "arrow.merge"
        case .roundabouts: return "arrow.triangle.2.circlepath"
        case .intersections: return "light.beacon.max.fill"
        case .backingUp: return "arrow.down.to.line"
        case .hills: return "mountain.2.fill"
        case .heavyTraffic: return "car.2.fill"
        }
    }
}
