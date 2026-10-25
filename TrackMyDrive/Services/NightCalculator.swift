import Foundation

/// Works out how many minutes of a drive fall inside "night", using either real sunset/sunrise at the
/// drive's location or a fixed clock window.
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

    /// The night that begins on the evening of `day` (or, for a fixed window that doesn't cross
    /// midnight, the window on `day` itself).
    static func nightInterval(eveningOf day: Date, latitude: Double?, longitude: Double?,
                              settings: AppSettings, calendar: Calendar) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        if settings.nightMode == .sunsetToSunrise, let latitude, let longitude {
            let sunset = SolarCalculator.sunEvent(.sunset, on: dayStart, latitude: latitude, longitude: longitude, calendar: calendar)
            let sunrise = SolarCalculator.sunEvent(.sunrise, on: nextDay, latitude: latitude, longitude: longitude, calendar: calendar)
            if let sunset, let sunrise {
                let offset = TimeInterval(settings.nightOffsetMinutes * 60)
                let s = sunset.addingTimeInterval(offset)
                let e = sunrise.addingTimeInterval(-offset)
                return e > s ? DateInterval(start: s, end: e) : nil
            }
            // Polar day/night: fall through to the fixed window rather than guessing.
        }

        let startM = clampMinutes(settings.fixedNightStartMinutes)
        let endM = clampMinutes(settings.fixedNightEndMinutes)
        guard startM != endM,
              let s = calendar.date(byAdding: .minute, value: startM, to: dayStart) else { return nil }
        let endBase = endM < startM ? nextDay : dayStart
        guard let e = calendar.date(byAdding: .minute, value: endM, to: endBase), e > s else { return nil }
        return DateInterval(start: s, end: e)
    }

    private static func clampMinutes(_ m: Int) -> Int { min(max(0, m), 24 * 60 - 1) }
}

/// Sunrise/sunset using the NOAA "Almanac for Computers" algorithm (accurate to about a minute
/// for populated latitudes).
enum SolarCalculator {
    enum Event { case sunrise, sunset }

    /// Official zenith: 90°50′, accounts for refraction and the sun's radius.
    private static let zenith = 90.833

    static func sunEvent(_ event: Event, on day: Date, latitude: Double, longitude: Double,
                         calendar: Calendar = .current) -> Date? {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let utcMidnight = utc.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day)),
              let n = utc.ordinality(of: .day, in: .year, for: utcMidnight) else { return nil }

        let rising = event == .sunrise
        let lngHour = longitude / 15
        let t = Double(n) + ((rising ? 6 : 18) - lngHour) / 24
        let m = 0.9856 * t - 3.289
        let l = normalize(m + 1.916 * sinD(m) + 0.020 * sinD(2 * m) + 282.634, 360)
        var ra = normalize(atanD(0.91764 * tanD(l)), 360)
        ra += floor(l / 90) * 90 - floor(ra / 90) * 90
        ra /= 15
        let sinDec = 0.39782 * sinD(l)
        let cosDec = cos(asin(sinDec))
        let cosH = (cosD(zenith) - sinDec * sinD(latitude)) / (cosDec * cosD(latitude))
        guard cosH.isFinite, cosH >= -1, cosH <= 1 else { return nil }
        let h = (rising ? 360 - acosD(cosH) : acosD(cosH)) / 15
        let localMean = h + ra - 0.06571 * t - 6.622
        let ut = normalize(localMean - lngHour, 24)

        var result = utcMidnight.addingTimeInterval(ut * 3600)
        // UT may land on the neighbouring UTC date; pull it onto the requested local day.
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return result }
        if result < dayStart { result.addTimeInterval(86_400) } else if result >= dayEnd { result.addTimeInterval(-86_400) }
        return result
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
