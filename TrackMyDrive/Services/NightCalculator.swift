import Foundation

/// Works out how many minutes of a drive fall inside "night", using either real sunset/sunrise at the
/// drive's location or a fixed clock window. Pass a calendar in the drive's own time zone.
enum NightCalculator {
    static func nightMinutes(start: Date, end: Date, latitude: Double?, longitude: Double?,
                             settings: AppSettings, calendar: Calendar = .current) -> Double {
        guard end > start else { return 0 }
        let lat = latitude ?? settings.lastKnownLatitude
        let lon = longitude ?? settings.lastKnownLongitude
        var total: TimeInterval = 0
        // Start the evening before, because a drive just after midnight belongs to the previous night.
        guard var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) else { return 0 }
        let lastDay = calendar.startOfDay(for: end)
        var iterations = 0
        while day <= lastDay, iterations < 400 {
            iterations += 1
            if let night = nightInterval(eveningOf: day, latitude: lat, longitude: lon, settings: settings, calendar: calendar) {
                let overlapStart = max(start, night.start)
                let overlapEnd = min(end, night.end)
                if overlapEnd > overlapStart { total += overlapEnd.timeIntervalSince(overlapStart) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total / 60
    }

    /// Whether driving at `date` would count as night.
    static func isNight(at date: Date, latitude: Double?, longitude: Double?, settings: AppSettings,
                        calendar: Calendar = .current) -> Bool {
        nightMinutes(start: date, end: date.addingTimeInterval(60), latitude: latitude, longitude: longitude,
                     settings: settings, calendar: calendar) > 0.5
    }

    /// The night that begins on the evening of `day`: from the first sunset after local noon to the
    /// following sunrise. Nights from consecutive days never overlap.
    static func nightInterval(eveningOf day: Date, latitude: Double?, longitude: Double?,
                              settings: AppSettings, calendar: Calendar) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        if settings.nightMode == .sunsetToSunrise, let latitude, let longitude,
           let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart),
           let nextNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: nextDay) {
            let offset = TimeInterval(settings.nightOffsetMinutes * 60)
            let horizon = noon.addingTimeInterval(36 * 3600)
            let sunset = SolarCalculator.events(.sunset, near: noon, latitude: latitude, longitude: longitude)
                .first { $0 >= noon && $0 < horizon }
            if let sunset {
                // No sunrise within a day and a half means the sun stays down (polar night): night runs
                // until next noon, where the next day's night picks up.
                let sunrise = SolarCalculator.events(.sunrise, near: sunset, latitude: latitude, longitude: longitude)
                    .first { $0 > sunset && $0 < sunset.addingTimeInterval(36 * 3600) }
                let s = sunset.addingTimeInterval(offset)
                let e = sunrise.map { $0.addingTimeInterval(-offset) } ?? nextNoon
                return e > s ? DateInterval(start: s, end: e) : nil
            }
            // No sunset this afternoon: either the sun never sets (no night) or never rises (all night).
            switch SolarCalculator.polarState(at: noon, latitude: latitude) {
            case .alwaysDown: return DateInterval(start: noon, end: nextNoon)
            case .alwaysUp, .normal: return nil
            }
        }

        // Fixed clock window, built from wall-clock times so DST days are right.
        let startM = clampMinutes(settings.fixedNightStartMinutes)
        let endM = clampMinutes(settings.fixedNightEndMinutes)
        guard startM != endM,
              let s = calendar.date(bySettingHour: startM / 60, minute: startM % 60, second: 0, of: dayStart) else { return nil }
        let endBase = endM < startM ? nextDay : dayStart
        guard let e = calendar.date(bySettingHour: endM / 60, minute: endM % 60, second: 0, of: endBase), e > s else { return nil }
        return DateInterval(start: s, end: e)
    }

    private static func clampMinutes(_ m: Int) -> Int { min(max(0, m), 24 * 60 - 1) }
}

/// Sunrise/sunset using the NOAA "Almanac for Computers" algorithm (accurate to about a minute
/// for populated latitudes). Works in UTC, so the result doesn't depend on the phone's time zone.
enum SolarCalculator {
    enum Event { case sunrise, sunset }
    enum PolarState { case normal, alwaysUp, alwaysDown }

    /// Official zenith: 90°50′, accounts for refraction and the sun's radius.
    private static let zenith = 90.833

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c
    }

    /// Every occurrence of `event` on the UTC days around `date`, in order.
    static func events(_ event: Event, near date: Date, latitude: Double, longitude: Double) -> [Date] {
        let cal = utc
        let base = cal.startOfDay(for: date)
        return (-1...2).compactMap { offset -> Date? in
            guard let day = cal.date(byAdding: .day, value: offset, to: base) else { return nil }
            return eventTime(event, utcDay: day, latitude: latitude, longitude: longitude)
        }.sorted()
    }

    /// Whether the sun stays up or down all day at `date` (inside the polar circles).
    static func polarState(at date: Date, latitude: Double) -> PolarState {
        let cal = utc
        guard let n = cal.ordinality(of: .day, in: .year, for: date) else { return .normal }
        let sinDec = 0.39782 * sinD(trueLongitude(Double(n) + 0.5))
        let cosDec = cos(asin(sinDec))
        let cosH = (cosD(zenith) - sinDec * sinD(latitude)) / (cosDec * cosD(latitude))
        if cosH > 1 { return .alwaysDown }
        if cosH < -1 { return .alwaysUp }
        return .normal
    }

    /// Kept for callers that want one event on a local day.
    static func sunEvent(_ event: Event, on day: Date, latitude: Double, longitude: Double,
                         calendar: Calendar = .current) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return events(event, near: dayStart, latitude: latitude, longitude: longitude)
            .first { $0 >= dayStart && $0 < dayEnd }
    }

    /// The event for UTC day `utcDay`, placed at its true instant (it may fall on the next UTC date).
    private static func eventTime(_ event: Event, utcDay: Date, latitude: Double, longitude: Double) -> Date? {
        guard let n = utc.ordinality(of: .day, in: .year, for: utcDay) else { return nil }
        let rising = event == .sunrise
        let lngHour = longitude / 15
        let t = Double(n) + ((rising ? 6 : 18) - lngHour) / 24
        let l = trueLongitude(t)
        var ra = normalize(atanD(0.91764 * tanD(l)), 360)
        ra += floor(l / 90) * 90 - floor(ra / 90) * 90
        ra /= 15
        let sinDec = 0.39782 * sinD(l)
        let cosDec = cos(asin(sinDec))
        let cosH = (cosD(zenith) - sinDec * sinD(latitude)) / (cosDec * cosD(latitude))
        guard cosH.isFinite, cosH >= -1, cosH <= 1 else { return nil }
        let h = (rising ? 360 - acosD(cosH) : acosD(cosH)) / 15
        let localMean = h + ra - 0.06571 * t - 6.622
        // Unwrapped UT: keep the event within the local solar day the formula aimed at.
        var ut = localMean - lngHour
        let approx = ((rising ? 6 : 18) - lngHour)
        while ut - approx > 12 { ut -= 24 }
        while approx - ut > 12 { ut += 24 }
        return utcDay.addingTimeInterval(ut * 3600)
    }

    private static func trueLongitude(_ t: Double) -> Double {
        let m = 0.9856 * t - 3.289
        return normalize(m + 1.916 * sinD(m) + 0.020 * sinD(2 * m) + 282.634, 360)
    }

    private static func normalize(_ v: Double, _ m: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
    private static func sinD(_ d: Double) -> Double { sin(d * .pi / 180) }
    private static func cosD(_ d: Double) -> Double { cos(d * .pi / 180) }
    private static func tanD(_ d: Double) -> Double { tan(d * .pi / 180) }
    private static func atanD(_ x: Double) -> Double { atan(x) * 180 / .pi }
    private static func acosD(_ x: Double) -> Double { acos(x) * 180 / .pi }
}
