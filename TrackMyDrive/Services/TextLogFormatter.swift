import Foundation

/// Plain-text and CSV versions of the log. The text version is designed to be saved in Apple Notes:
/// it's readable on its own and ends with a restore block the app can import.
enum TextLogFormatter {
    static func notesBackup(drives: [Drive], settings: AppSettings, archive: LogArchive) -> String {
        var out: [String] = ["🚗 TrackMyDrive — Driving Log Backup", "Saved: \(Fmt.dateTime.string(from: Date()))"]
        // One readable section per driver; the restore block below always holds everyone.
        let profiles = archive.settings.allDrivers
        for profile in profiles {
            let driverDrives = profiles.count == 1 ? archive.drives : archive.drives.filter { $0.driverID == profile.id }
            if profiles.count > 1 { out.append(""); out.append("════════ \(profile.displayName.uppercased()) ════════") }
            out.append(contentsOf: driverSection(drives: driverDrives, settings: archive.settings.viewed(as: profile)))
        }
        out.append("")
        out.append("RESTORE DATA — don't edit below this line.")
        out.append("To recover: open TrackMyDrive ▸ Settings ▸ Restore From Backup, then paste this whole note.")
        out.append(BackupCodec.textBlock(for: archive))
        return out.joined(separator: "\n")
    }

    private static func driverSection(drives: [Drive], settings: AppSettings) -> [String] {
        let stats = LogStats(drives: drives, settings: settings)
        let unit = settings.distanceUnit
        var out: [String] = []
        var who: [String] = []
        if !settings.studentName.isEmpty { who.append("Driver: \(settings.studentName)") }
        if !settings.permitNumber.isEmpty { who.append("Permit #: \(settings.permitNumber)") }
        if let state = settings.statePreset { who.append("State: \(state.name)") }
        if !who.isEmpty { out.append(who.joined(separator: " · ")) }
        out.append("")
        out.append("TOTALS")
        out.append("Total: \(Fmt.duration(minutes: stats.totalMinutes)) of \(Fmt.hoursShort(minutes: settings.totalGoalMinutes))h goal (\(Int((stats.totalProgress * 100).rounded()))%)")
        out.append("Night: \(Fmt.duration(minutes: stats.nightMinutes)) of \(Fmt.hoursShort(minutes: settings.nightGoalMinutes))h goal (\(Int((stats.nightProgress * 100).rounded()))%)")
        if stats.hasWeatherGoal {
            out.append("Bad weather: \(Fmt.duration(minutes: stats.adverseWeatherMinutes)) of \(Fmt.hoursShort(minutes: settings.weatherGoalMinutes))h goal")
        }
        out.append("Day: \(Fmt.duration(minutes: stats.dayMinutes))")
        out.append("Drives: \(stats.driveCount) · Distance: \(Fmt.distance(meters: stats.distanceMeters, unit: unit))")
        out.append("")
        out.append("DRIVES (newest first)")
        if drives.isEmpty { out.append("No drives logged yet.") }
        let ordered = drives.sorted { $0.startDate > $1.startDate }
        for (i, d) in ordered.enumerated() {
            let number = ordered.count - i
            out.append("")
            out.append("#\(number)  \(Fmt.fullDate.string(from: d.startDate))  \(Fmt.time.string(from: d.startDate)) – \(Fmt.time.string(from: d.endDate))")
            var line = "    \(Fmt.duration(minutes: d.totalMinutes)) (night \(Fmt.duration(minutes: d.clampedNightMinutes)))"
            if d.distanceMeters != nil { line += " · \(Fmt.distance(meters: d.distanceMeters, unit: unit))" }
            if !d.supervisor.isEmpty { line += " · Supervisor: \(d.supervisor)" }
            out.append(line)
            let cond = Fmt.conditions(d)
            if !cond.isEmpty { out.append("    \(cond)") }
            if let route = d.routeSummary { out.append("    Route: \(route)") }
            if !d.skills.isEmpty { out.append("    Practiced: \(d.skills.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: ", "))") }
            if !d.notes.isEmpty { out.append("    Notes: \(d.notes.replacingOccurrences(of: "\n", with: " "))") }
        }
        return out
    }

    static func csv(drives: [Drive], settings: AppSettings) -> String {
        let unit = settings.distanceUnit
        var rows = [["Date", "Start", "End", "Total Hours", "Night Hours", "Day Hours", "Distance (\(unit.abbreviation))",
                     "Supervisor", "Vehicle", "Weather", "Roads", "Skills", "Route", "Notes"]]
        for d in drives.sorted(by: { $0.startDate < $1.startDate }) {
            rows.append([
                Fmt.csvDate.string(from: d.startDate),
                Fmt.csvTime.string(from: d.startDate),
                Fmt.csvTime.string(from: d.endDate),
                Fmt.hours(minutes: d.totalMinutes),
                Fmt.hours(minutes: d.clampedNightMinutes),
                Fmt.hours(minutes: d.dayMinutes),
                d.distanceMeters.map { String(format: "%.1f", unit.value(fromMeters: $0)) } ?? "",
                d.supervisor,
                d.vehicle,
                d.weather.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: "; "),
                d.roads.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: "; "),
                d.skills.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: "; "),
                d.routeSummary ?? "",
                d.notes,
            ])
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ field: String) -> String {
        var f = field
        // Stop spreadsheet apps from treating text as a formula.
        if let first = f.first, "=+-@".contains(first), Double(f) == nil { f = "'" + f }
        guard f.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return f }
        return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
