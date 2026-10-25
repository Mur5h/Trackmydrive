import Foundation

enum Fmt {
    /// "1h 05m", "45m", "0m".
    static func duration(minutes: Double) -> String {
        let total = Int(max(0, minutes).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : String(format: "%dh %02dm", h, m)
    }

    static func duration(seconds: TimeInterval) -> String { duration(minutes: seconds / 60) }

    /// "1.5" style decimal hours, for the PDF and CSV.
    static func hours(minutes: Double) -> String {
        String(format: "%.2f", max(0, minutes) / 60)
    }

    /// "23.4" (number only) or "23.4 hrs".
    static func hoursShort(minutes: Double) -> String {
        let h = max(0, minutes) / 60
        return h >= 100 || h.rounded() == h ? String(format: "%.0f", h) : String(format: "%.1f", h)
    }

    /// Stopwatch style: "1:05:09" or "05:09".
    static func clock(seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func distance(meters: Double?, unit: DistanceUnit, decimals: Int = 1) -> String {
        guard let meters else { return "—" }
        return String(format: "%.\(decimals)f %@", unit.value(fromMeters: meters), unit.abbreviation)
    }

    static func speed(metersPerSecond: Double, unit: DistanceUnit) -> String {
        let perHour = unit.value(fromMeters: metersPerSecond * 3600)
        return String(format: "%.0f %@", perHour, unit.speedLabel)
    }

    static func timeOfDay(minutes: Int) -> String {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let date = Calendar.current.date(from: comps) ?? Date()
        return time.string(from: date)
    }

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMMM d yyyy")
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }()

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let csvDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let csvTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        if abs(date.timeIntervalSince(now)) < 60 { return "just now" }
        return f.localizedString(for: date, relativeTo: now)
    }

    static func conditions(_ drive: Drive) -> String {
        let parts = drive.weather.sorted { $0.rawValue < $1.rawValue }.map(\.label)
            + drive.roads.sorted { $0.rawValue < $1.rawValue }.map(\.label)
        return parts.joined(separator: ", ")
    }
}
