import Foundation
import Combine
import CoreLocation

/// Single source of truth for the driving log. Every change is written to disk immediately
/// (atomically, keeping the previous version), and a debounced pass refreshes the daily JSON
/// snapshot plus the PDF and text copies in the app's Files folder.
@MainActor
final class DriveStore: ObservableObject {
    static let shared = DriveStore()

    @Published private(set) var drives: [Drive] = []
    @Published private(set) var recentlyDeleted: [DeletedDrive] = []
    @Published private(set) var activeDrive: ActiveDrive?
    @Published var settings = AppSettings() {
        didSet {
            guard !isLoading, settings != oldValue else { return }
            scheduleSave()
        }
    }
    /// Shown once on the home screen when the log had to be recovered from a backup.
    @Published var loadWarning: String?
    @Published private(set) var lastSaveError: String?

    static let trashRetentionDays = 30

    private var isLoading = false
    /// Set when the log file exists but couldn't be read at all (e.g. the device was locked).
    /// While set, nothing is written, so a good file is never replaced by an empty one.
    private var writesBlocked = false
    private var saveTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var lastActivePersist = Date.distantPast
    private let fm = FileManager.default
    private let tracker: LocationTracker
    private let geocoder = CLGeocoder()

    private init() {
        tracker = LocationTracker.shared
        load()
        tracker.onLocation = { [weak self] location in
            self?.record(location: location)
        }
        if let active = activeDrive, active.stoppedAt == nil, settings.trackLocation {
            tracker.start()
        }
    }

    var stats: LogStats { LogStats(drives: drives, settings: settings) }

    // MARK: - Drives

    func add(_ drive: Drive) {
        var d = drive
        d.createdAt = Date()
        d.modifiedAt = Date()
        drives.removeAll { $0.id == d.id }
        drives.append(d)
        rememberNames(from: d)
        sortDrives()
        saveNow()
    }

    func update(_ drive: Drive) {
        guard let i = drives.firstIndex(where: { $0.id == drive.id }) else { add(drive); return }
        var d = drive
        d.modifiedAt = Date()
        drives[i] = d
        rememberNames(from: d)
        sortDrives()
        saveNow()
    }

    func delete(_ ids: Set<UUID>) {
        let now = Date()
        let removed = drives.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        drives.removeAll { ids.contains($0.id) }
        recentlyDeleted.removeAll { ids.contains($0.id) }
        recentlyDeleted.insert(contentsOf: removed.map { DeletedDrive(drive: $0, deletedAt: now) }, at: 0)
        saveNow()
    }

    func deleteAll() { delete(Set(drives.map(\.id))) }

    func restoreDeleted(_ item: DeletedDrive) {
        recentlyDeleted.removeAll { $0.id == item.id }
        var d = item.drive
        d.modifiedAt = Date()
        drives.removeAll { $0.id == d.id }
        drives.append(d)
        sortDrives()
        saveNow()
    }

    func permanentlyDelete(_ item: DeletedDrive) {
        recentlyDeleted.removeAll { $0.id == item.id }
        saveNow()
    }

    func emptyRecentlyDeleted() {
        recentlyDeleted.removeAll()
        saveNow()
    }

    func drive(withID id: UUID) -> Drive? { drives.first { $0.id == id } }

    func computedNightMinutes(for drive: Drive) -> Double {
        NightCalculator.nightMinutes(start: drive.startDate, end: drive.endDate,
                                     latitude: drive.startLatitude, longitude: drive.startLongitude,
                                     settings: settings)
    }

    /// Re-runs the night calculation for every drive whose night time wasn't typed in by hand.
    @discardableResult
    func recalculateNightTimes() -> Int {
        var changed = 0
        for i in drives.indices where !drives[i].nightMinutesIsManual {
            let value = computedNightMinutes(for: drives[i])
            if abs(value - drives[i].nightMinutes) > 0.01 {
                drives[i].nightMinutes = value
                drives[i].modifiedAt = Date()
                changed += 1
            }
        }
        if changed > 0 { saveNow() }
        return changed
    }

    private func sortDrives() {
        drives.sort { $0.startDate > $1.startDate }
    }

    private func rememberNames(from drive: Drive) {
        let sup = drive.supervisor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sup.isEmpty, !settings.supervisors.contains(sup) { settings.supervisors.append(sup) }
        let veh = drive.vehicle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !veh.isEmpty, !settings.vehicles.contains(veh) { settings.vehicles.append(veh) }
    }

    // MARK: - Live drive

    func startDrive(supervisor: String, vehicle: String) {
        guard activeDrive == nil else { return }
        activeDrive = ActiveDrive(startDate: Date(), supervisor: supervisor, vehicle: vehicle)
        persistActive(force: true)
        if settings.trackLocation { tracker.start() }
    }

    func stopDrive() {
        guard var a = activeDrive, a.stoppedAt == nil else { return }
        a.stoppedAt = Date()
        activeDrive = a
        persistActive(force: true)
        tracker.stop()
        if let lat = a.lastLatitude, let lon = a.lastLongitude {
            geocode(CLLocation(latitude: lat, longitude: lon), isStart: false)
        }
    }

    func resumeDrive() {
        guard var a = activeDrive, a.stoppedAt != nil else { return }
        a.stoppedAt = nil
        activeDrive = a
        persistActive(force: true)
        if settings.trackLocation { tracker.start() }
    }

    func updateActive(supervisor: String, vehicle: String) {
        guard var a = activeDrive else { return }
        a.supervisor = supervisor
        a.vehicle = vehicle
        activeDrive = a
        persistActive(force: true)
    }

    /// A drive pre-filled from the live drive, for the review screen.
    func draftFromActiveDrive() -> Drive? {
        guard let a = activeDrive else { return nil }
        var d = Drive(startDate: a.startDate, endDate: a.stoppedAt ?? Date())
        d.id = a.id
        d.source = .tracked
        d.supervisor = a.supervisor
        d.vehicle = a.vehicle
        d.distanceMeters = a.lastFixDate == nil ? nil : a.distanceMeters
        d.startLatitude = a.startLatitude
        d.startLongitude = a.startLongitude
        d.startPlaceName = a.startPlaceName
        d.endPlaceName = a.endPlaceName
        d.route = a.route
        d.nightMinutes = computedNightMinutes(for: d)
        return d
    }

    func finishActiveDrive(with draft: Drive) {
        var d = draft
        if let a = activeDrive {
            if d.startPlaceName == nil { d.startPlaceName = a.startPlaceName }
            if d.endPlaceName == nil { d.endPlaceName = a.endPlaceName }
        }
        add(d)
        clearActive()
    }

    func discardActiveDrive() {
        clearActive()
    }

    private func clearActive() {
        tracker.stop()
        activeDrive = nil
        try? fm.removeItem(at: StorePaths.activeDrive)
    }

    private func record(location: CLLocation) {
        guard var a = activeDrive, a.stoppedAt == nil else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 65,
              location.timestamp >= a.startDate.addingTimeInterval(-5),
              abs(location.timestamp.timeIntervalSinceNow) < 30 else { return }
        let coord = location.coordinate

        if a.startLatitude == nil {
            a.startLatitude = coord.latitude
            a.startLongitude = coord.longitude
            settings.lastKnownLatitude = coord.latitude
            settings.lastKnownLongitude = coord.longitude
            geocode(location, isStart: true)
        }

        if let lat = a.lastLatitude, let lon = a.lastLongitude, let lastFix = a.lastFixDate {
            let d = location.distance(from: CLLocation(latitude: lat, longitude: lon))
            // Ignore GPS jitter while parked; keep the old anchor so slow creeping still adds up.
            if d < max(4, location.horizontalAccuracy * 0.5) { return }
            let dt = max(location.timestamp.timeIntervalSince(lastFix), 0.5)
            // A jump faster than ~170 mph is a bad fix (or a long gap); re-anchor without counting it.
            if d / dt <= 75 { a.distanceMeters += d }
        }
        a.lastLatitude = coord.latitude
        a.lastLongitude = coord.longitude
        a.lastFixDate = location.timestamp
        if location.speed >= 0, location.speed < 75 {
            a.maxSpeedMetersPerSecond = max(a.maxSpeedMetersPerSecond, location.speed)
        }

        let point = RoutePoint(lat: coord.latitude, lon: coord.longitude)
        if let last = a.route.last {
            if location.distance(from: CLLocation(latitude: last.lat, longitude: last.lon)) >= 25 { a.route.append(point) }
        } else {
            a.route.append(point)
        }
        if a.route.count > 4000 {
            // Thin the route but always keep the newest point.
            var thinned = stride(from: 0, to: a.route.count, by: 2).map { a.route[$0] }
            if thinned.last != a.route.last, let last = a.route.last { thinned.append(last) }
            a.route = thinned
        }

        activeDrive = a
        persistActive(force: false)
    }

    private func geocode(_ location: CLLocation, isStart: Bool) {
        Task { [weak self] in
            guard let self else { return }
            guard let placemark = try? await self.geocoder.reverseGeocodeLocation(location).first else { return }
            let parts = [placemark.thoroughfare, placemark.locality].compactMap { $0 }
            let name = parts.isEmpty ? placemark.name : parts.joined(separator: ", ")
            guard let name, var a = self.activeDrive else { return }
            if isStart { a.startPlaceName = name } else { a.endPlaceName = name }
            self.activeDrive = a
            self.persistActive(force: true)
        }
    }

    private func persistActive(force: Bool) {
        guard let a = activeDrive else { return }
        guard force || Date().timeIntervalSince(lastActivePersist) > 10 else { return }
        lastActivePersist = Date()
        guard let data = try? BackupCodec.makeEncoder(pretty: false).encode(a) else { return }
        try? data.write(to: StorePaths.activeDrive, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Backups

    struct ImportSummary {
        var added = 0
        var updated = 0
        var unchanged = 0
        var description: String {
            var parts: [String] = []
            if added > 0 { parts.append("\(added) drive\(added == 1 ? "" : "s") added") }
            if updated > 0 { parts.append("\(updated) updated") }
            if unchanged > 0 { parts.append("\(unchanged) already in your log") }
            return parts.isEmpty ? "The backup didn't contain any drives." : parts.joined(separator: ", ") + "."
        }
    }

    /// Merges a backup into the log. Nothing is ever removed: drives already present are kept unless
    /// the backup has a newer edit of the same drive.
    func importArchive(_ archive: LogArchive, restoreSettings: Bool) -> ImportSummary {
        writeSnapshot(suffix: "before-restore")
        var summary = ImportSummary()
        for incoming in archive.drives {
            if let i = drives.firstIndex(where: { $0.id == incoming.id }) {
                if incoming.modifiedAt > drives[i].modifiedAt {
                    // Keep the route if the backup copy (e.g. from Notes) doesn't carry one.
                    var merged = incoming
                    if merged.route.isEmpty { merged.route = drives[i].route }
                    drives[i] = merged
                    summary.updated += 1
                } else {
                    summary.unchanged += 1
                }
            } else {
                drives.append(incoming)
                recentlyDeleted.removeAll { $0.id == incoming.id }
                summary.added += 1
            }
        }
        if restoreSettings {
            var s = archive.settings
            s.hasOnboarded = true
            s.lastKnownLatitude = s.lastKnownLatitude ?? settings.lastKnownLatitude
            s.lastKnownLongitude = s.lastKnownLongitude ?? settings.lastKnownLongitude
            s.lastExternalBackup = settings.lastExternalBackup
            s.lastNotesBackup = settings.lastNotesBackup
            s.supervisors = merge(settings.supervisors, s.supervisors)
            s.vehicles = merge(settings.vehicles, s.vehicles)
            settings = s
        } else {
            settings.supervisors = merge(settings.supervisors, archive.settings.supervisors)
            settings.vehicles = merge(settings.vehicles, archive.settings.vehicles)
        }
        sortDrives()
        saveNow()
        return summary
    }

    private func merge(_ a: [String], _ b: [String]) -> [String] {
        var out = a
        for x in b where !x.isEmpty && !out.contains(x) { out.append(x) }
        return out
    }

    var archive: LogArchive {
        LogArchive(settings: settings, drives: drives, recentlyDeleted: recentlyDeleted)
    }

    /// Drives added or edited since the last backup that left the device.
    var changesSinceExternalBackup: Int {
        guard let last = settings.lastExternalBackup else { return drives.count }
        return drives.filter { $0.modifiedAt > last }.count
    }

    func markExternalBackup(toNotes: Bool) {
        settings.lastExternalBackup = Date()
        if toNotes { settings.lastNotesBackup = Date() }
        saveNow()
    }

    /// Writes everything to disk right away (call when the app goes to the background).
    func flush() {
        if saveTask != nil { saveNow() }
        persistActive(force: true)
        if exportTask != nil {
            exportTask?.cancel()
            exportTask = nil
            writeExports()
        }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard !writesBlocked else {
            lastSaveError = "Your log couldn't be opened, so changes aren't being saved to protect it. Restart the app."
            return
        }
        do {
            let data = try BackupCodec.encode(archive)
            let primary = StorePaths.primaryLog
            if fm.fileExists(atPath: primary.path) {
                try? fm.removeItem(at: StorePaths.previousLog)
                try? fm.copyItem(at: primary, to: StorePaths.previousLog)
            }
            try data.write(to: primary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastSaveError = nil
        } catch {
            lastSaveError = "Couldn't save your log: \(error.localizedDescription)"
        }
        scheduleExports()
    }

    private func scheduleExports() {
        exportTask?.cancel()
        exportTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.exportTask = nil
            self.writeExports()
        }
    }

    /// Refreshes the copies that live in Files ▸ On My iPhone ▸ TrackMyDrive.
    private func writeExports() {
        guard !writesBlocked else { return }
        writeSnapshot(suffix: nil)
        let stats = self.stats
        if let pdf = PDFLogRenderer.render(drives: drives, settings: settings, stats: stats) {
            try? pdf.write(to: StorePaths.documentsPDF, options: .atomic)
        }
        let text = TextLogFormatter.notesBackup(drives: drives, settings: settings, archive: archive)
        try? text.data(using: .utf8)?.write(to: StorePaths.documentsText, options: .atomic)
    }

    private func writeSnapshot(suffix: String?) {
        guard !writesBlocked, !drives.isEmpty || !recentlyDeleted.isEmpty else { return }
        let dir = StorePaths.snapshotsDirectory
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = suffix == nil ? "yyyy-MM-dd" : "yyyy-MM-dd-HHmmss"
        let name = "TrackMyDrive-\(f.string(from: Date()))\(suffix.map { "-\($0)" } ?? "").json"
        guard let data = try? BackupCodec.encode(archive, pretty: true) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        pruneSnapshots(in: dir, keep: 30)
    }

    private func snapshotFiles() -> [URL] {
        let dir = StorePaths.snapshotsDirectory
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { modDate($0) > modDate($1) }
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func pruneSnapshots(in dir: URL, keep: Int) {
        let files = snapshotFiles()
        guard files.count > keep else { return }
        for url in files.dropFirst(keep) { try? fm.removeItem(at: url) }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        let primary = StorePaths.primaryLog
        var loaded: LogArchive?
        var recoveredFrom: String?

        if fm.fileExists(atPath: primary.path) {
            do {
                let data = try Data(contentsOf: primary)
                do {
                    loaded = try BackupCodec.decode(data)
                } catch {
                    // Damaged file: keep a copy for support, then fall back to backups below.
                    let stamp = Int(Date().timeIntervalSince1970)
                    try? fm.copyItem(at: primary, to: StorePaths.appSupport.appendingPathComponent("log.damaged-\(stamp).json"))
                }
            } catch {
                writesBlocked = true
                loadWarning = "TrackMyDrive couldn't open your log right now. Nothing has been changed. Please close and reopen the app."
                return
            }
        }

        if loaded == nil {
            let fallbacks = [StorePaths.previousLog] + snapshotFiles()
            for url in fallbacks where fm.fileExists(atPath: url.path) {
                if let data = try? Data(contentsOf: url), let a = try? BackupCodec.decode(data) {
                    loaded = a
                    recoveredFrom = url.lastPathComponent
                    break
                }
            }
            if fm.fileExists(atPath: primary.path) {
                loadWarning = recoveredFrom != nil
                    ? "Your log file was damaged, so it was recovered from a backup (\(recoveredFrom!)). Check that your latest drives are there; if not, use Settings ▸ Restore with your Notes backup."
                    : "Your log file was damaged and no automatic backup could be read. Use Settings ▸ Restore with your Notes backup."
            }
        }

        if let loaded {
            settings = loaded.settings
            drives = loaded.drives.sorted { $0.startDate > $1.startDate }
            let cutoff = Calendar.current.date(byAdding: .day, value: -Self.trashRetentionDays, to: Date()) ?? .distantPast
            recentlyDeleted = loaded.recentlyDeleted.filter { $0.deletedAt > cutoff }
        }

        if let data = try? Data(contentsOf: StorePaths.activeDrive),
           let a = try? BackupCodec.makeDecoder().decode(ActiveDrive.self, from: data) {
            activeDrive = a
        }

        if recoveredFrom != nil {
            // Re-create the primary file from the recovered copy.
            DispatchQueue.main.async { [weak self] in self?.saveNow() }
        }
    }
}

enum StorePaths {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("TrackMyDrive", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var primaryLog: URL { appSupport.appendingPathComponent("log.json") }
    static var previousLog: URL { appSupport.appendingPathComponent("log.previous.json") }
    static var activeDrive: URL { appSupport.appendingPathComponent("active-drive.json") }
    static var snapshotsDirectory: URL {
        let url = documents.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var documentsPDF: URL { documents.appendingPathComponent("TrackMyDrive Driving Log.pdf") }
    static var documentsText: URL { documents.appendingPathComponent("TrackMyDrive Driving Log.txt") }
}
