import Foundation

/// Totals and derived figures for a set of drives. Cheap to build; views create it on demand.
struct LogStats {
    let drives: [Drive]
    let settings: AppSettings

    init(drives: [Drive], settings: AppSettings) {
        self.drives = drives
        self.settings = settings
        totalMinutes = drives.reduce(0) { $0 + $1.totalMinutes }
        nightMinutes = drives.reduce(0) { $0 + $1.clampedNightMinutes }
        distanceMeters = drives.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
        adverseWeatherMinutes = drives.filter { $0.weather.contains(where: \.isAdverse) }.reduce(0) { $0 + $1.totalMinutes }
    }

    let totalMinutes: Double
    let nightMinutes: Double
    let distanceMeters: Double
    let adverseWeatherMinutes: Double

    var dayMinutes: Double { totalMinutes - nightMinutes }
    var driveCount: Int { drives.count }
    var averageMinutes: Double { drives.isEmpty ? 0 : totalMinutes / Double(drives.count) }
    var longestDrive: Drive? { drives.max { $0.duration < $1.duration } }

    var totalProgress: Double { progress(totalMinutes, settings.totalGoalMinutes) }
    var nightProgress: Double { progress(nightMinutes, settings.nightGoalMinutes) }
    var totalRemainingMinutes: Double { max(0, settings.totalGoalMinutes - totalMinutes) }
    var nightRemainingMinutes: Double { max(0, settings.nightGoalMinutes - nightMinutes) }
    var goalsComplete: Bool { totalRemainingMinutes <= 0 && nightRemainingMinutes <= 0 }

    private func progress(_ value: Double, _ goal: Double) -> Double {
        guard goal > 0 else { return value > 0 ? 1 : 0 }
        return min(1, value / goal)
    }

    /// Minutes driven in the last `days` days.
    func minutes(inLast days: Int, now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return 0 }
        return drives.filter { $0.startDate >= cutoff }.reduce(0) { $0 + $1.totalMinutes }
    }

    /// Estimated date the total goal is met, based on the pace of the last 30 days.
    func projectedCompletion(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard totalRemainingMinutes > 0 || nightRemainingMinutes > 0,
              let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
        let recent = drives.filter { $0.startDate >= cutoff }
        let totalRecent = recent.reduce(0) { $0 + $1.totalMinutes }
        let nightRecent = recent.reduce(0) { $0 + $1.clampedNightMinutes }
        // Use whichever goal will take longer to reach at the current pace.
        var days = 0.0
        if totalRemainingMinutes > 0 {
            guard totalRecent > 0 else { return nil }
            days = totalRemainingMinutes / (totalRecent / 30)
        }
        if nightRemainingMinutes > 0 {
            guard nightRecent > 0 else { return nil }
            days = max(days, nightRemainingMinutes / (nightRecent / 30))
        }
        guard days.isFinite, days < 3650 else { return nil }
        return calendar.date(byAdding: .day, value: Int(days.rounded(.up)), to: now)
    }

    /// Consecutive days (ending today or yesterday) with at least one drive.
    func currentStreak(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(drives.map { calendar.startOfDay(for: $0.startDate) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    struct WeekBucket: Identifiable {
        let weekStart: Date
        let dayMinutes: Double
        let nightMinutes: Double
        var id: Date { weekStart }
    }

    /// Day/night minutes per week for the last `count` weeks, oldest first.
    func weeklyBuckets(count: Int, now: Date = Date(), calendar: Calendar = .current) -> [WeekBucket] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var buckets: [WeekBucket] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            let inWeek = drives.filter { $0.startDate >= start && $0.startDate < end }
            let night = inWeek.reduce(0) { $0 + $1.clampedNightMinutes }
            let total = inWeek.reduce(0) { $0 + $1.totalMinutes }
            buckets.append(WeekBucket(weekStart: start, dayMinutes: total - night, nightMinutes: night))
        }
        return buckets
    }

    struct CategoryTotal: Identifiable {
        let id: String
        let label: String
        let symbol: String
        let minutes: Double
    }

    struct SkillCount: Identifiable {
        let skill: DrivingSkill
        let count: Int
        var id: String { skill.rawValue }
    }

    func minutesByWeather() -> [CategoryTotal] {
        WeatherCondition.allCases.map { w in
            CategoryTotal(id: w.rawValue, label: w.label, symbol: w.symbol,
                          minutes: drives.filter { $0.weather.contains(w) }.reduce(0) { $0 + $1.totalMinutes })
        }.filter { $0.minutes > 0 }
    }

    func minutesByRoad() -> [CategoryTotal] {
        RoadType.allCases.map { r in
            CategoryTotal(id: r.rawValue, label: r.label, symbol: r.symbol,
                          minutes: drives.filter { $0.roads.contains(r) }.reduce(0) { $0 + $1.totalMinutes })
        }.filter { $0.minutes > 0 }
    }

    func skillCounts() -> [SkillCount] {
        DrivingSkill.allCases.map { s in SkillCount(skill: s, count: drives.filter { $0.skills.contains(s) }.count) }
    }

    func minutesBySupervisor() -> [CategoryTotal] {
        var map: [String: Double] = [:]
        for d in drives {
            let name = d.supervisor.trimmingCharacters(in: .whitespaces)
            map[name.isEmpty ? "Unspecified" : name, default: 0] += d.totalMinutes
        }
        return map.sorted { $0.value > $1.value }
            .map { CategoryTotal(id: $0.key, label: $0.key, symbol: "person.fill", minutes: $0.value) }
    }
}
