import Foundation
import Combine
import CoreLocation

/// Single source of truth for the driving log. Every change is written to disk immediately
/// (atomically, keeping the previous version), and a debounced pass refreshes the daily JSON
/// snapshot plus the PDF and text copies in the app's Files folder.
@MainActor
final class DriveStore: ObservableObject {
    static let shared = DriveStore()

    /// Every driver's drives. Screens use `drives`, which is just the active driver's.
    @Published private(set) var allDrives: [Drive] = []
    var drives: [Drive] { allDrives.filter { $0.driverID == settings.activeDriverID } }
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
    /// The iCloud Drive (or other) folder that gets a fresh copy of the log after every change.
    @Published private(set) var cloudFolder: CloudFolderState? = CloudFolderBackup.loadState()
    @Published private(set) var isWritingCloudFolder = false
    private var cloudWritePending = false

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

    /// Returns false if the log couldn't be written to disk (the drive is still kept in memory).
    @discardableResult
    func add(_ drive: Drive) -> Bool {
        var d = drive
        d.createdAt = allDrives.first { $0.id == d.id }?.createdAt ?? Date()
        d.modifiedAt = Date()
        if d.driverID == nil { d.driverID = settings.activeDriverID }
        allDrives.removeAll { $0.id == d.id }
        recentlyDeleted.removeAll { $0.id == d.id }
        allDrives.append(d)
        rememberNames(from: d)
        sortDrives()
        return saveNow()
    }

    @discardableResult
    func update(_ drive: Drive) -> Bool {
        guard let i = allDrives.firstIndex(where: { $0.id == drive.id }) else { return add(drive) }
        var d = drive
        d.modifiedAt = Date()
        allDrives[i] = d
        rememberNames(from: d)
        sortDrives()
        return saveNow()
    }

    func delete(_ ids: Set<UUID>) {
        let now = Date()
        let removed = allDrives.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        allDrives.removeAll { ids.contains($0.id) }
        recentlyDeleted.removeAll { ids.contains($0.id) }
        recentlyDeleted.insert(contentsOf: removed.map { DeletedDrive(drive: $0, deletedAt: now) }, at: 0)
        saveNow()
    }

    func deleteAll() { delete(Set(drives.map(\.id))) }

    func restoreDeleted(_ item: DeletedDrive) {
        recentlyDeleted.removeAll { $0.id == item.id }
        var d = item.drive
        d.modifiedAt = Date()
        allDrives.removeAll { $0.id == d.id }
        allDrives.append(d)
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

    func drive(withID id: UUID) -> Drive? { allDrives.first { $0.id == id } }

    func computedNightMinutes(for drive: Drive) -> Double {
        NightCalculator.nightMinutes(start: drive.startDate, end: drive.endDate,
                                     latitude: drive.startLatitude, longitude: drive.startLongitude,
                                     settings: settings, calendar: drive.calendar)
    }

    /// Re-runs the night calculation for every drive whose night time wasn't typed in by hand.
    @discardableResult
    func recalculateNightTimes() -> Int {
        writeSnapshot(suffix: "before-recalculate")
        var changed = 0
        for i in allDrives.indices where !allDrives[i].nightMinutesIsManual {
            let value = computedNightMinutes(for: allDrives[i])
            if abs(value - allDrives[i].nightMinutes) > 0.01 {
                allDrives[i].nightMinutes = value
                allDrives[i].modifiedAt = Date()
                changed += 1
            }
        }
        if changed > 0 { saveNow() }
        return changed
    }

    private func sortDrives() {
        allDrives.sort { $0.startDate > $1.startDate }
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
        var a = ActiveDrive(startDate: Date(), supervisor: supervisor, vehicle: vehicle)
        a.driverID = settings.activeDriverID
        activeDrive = a
        persistActive(force: true)
        if settings.trackLocation { tracker.start() }
        NotificationService.scheduleStillDriving(startedAt: a.startDate)
    }

    func stopDrive() {
        guard var a = activeDrive, a.stoppedAt == nil else { return }
        a.stoppedAt = Date()
        activeDrive = a
        persistActive(force: true)
        tracker.stop()
        NotificationService.cancelStillDriving()
        if let lat = a.lastLatitude, let lon = a.lastLongitude {
            geocode(CLLocation(latitude: lat, longitude: lon), isStart: false, driveID: a.id)
        }
    }

    func resumeDrive() {
        guard var a = activeDrive, a.stoppedAt != nil else { return }
        a.stoppedAt = nil
        activeDrive = a
        persistActive(force: true)
        if settings.trackLocation { tracker.start() }
        NotificationService.scheduleStillDriving(startedAt: a.startDate)
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
        d.timeZoneIdentifier = a.timeZoneIdentifier
        d.driverID = a.driverID ?? settings.activeDriverID
        d.nightMinutes = computedNightMinutes(for: d)
        return d
    }

    /// Saves the reviewed drive. The live drive is only cleared once the log is safely on disk;
    /// otherwise it stays (and stays saved in its own file) so the hours can't be lost.
    @discardableResult
    func finishActiveDrive(with draft: Drive) -> Bool {
        var d = draft
        if let a = activeDrive {
            if d.startPlaceName == nil { d.startPlaceName = a.startPlaceName }
            if d.endPlaceName == nil { d.endPlaceName = a.endPlaceName }
        }
        guard add(d) else {
            allDrives.removeAll { $0.id == d.id }
            return false
        }
        clearActive()
        return true
    }

    func discardActiveDrive() {
        clearActive()
    }

    private func clearActive() {
        tracker.stop()
        NotificationService.cancelStillDriving()
        activeDrive = nil
        guard !writesBlocked else { return }
        try? fm.removeItem(at: StorePaths.activeDrive)
    }

    private func record(location: CLLocation) {
        guard var a = activeDrive, a.stoppedAt == nil else { return }
        guard location.horizontalAccuracy >= 0,
              location.timestamp >= a.startDate.addingTimeInterval(-5) else { return }
        // Fixes can arrive in delayed batches; take every one newer than the last, in order.
        if let lastFix = a.lastFixDate {
            guard location.timestamp > lastFix else { return }
        } else if abs(location.timestamp.timeIntervalSinceNow) > 60 {
            return
        }
        let coord = location.coordinate

        // Even a rough fix (e.g. Precise Location off) is plenty for sunset times.
        if a.startLatitude == nil, location.horizontalAccuracy <= 5000 {
            a.startLatitude = coord.latitude
            a.startLongitude = coord.longitude
            settings.lastKnownLatitude = coord.latitude
            settings.lastKnownLongitude = coord.longitude
            geocode(location, isStart: true, driveID: a.id)
            activeDrive = a
        }
        guard location.horizontalAccuracy <= 65 else { return }

        if let lat = a.lastLatitude, let lon = a.lastLongitude, let lastFix = a.lastFixDate {
            let d = location.distance(from: CLLocation(latitude: lat, longitude: lon))
            // Ignore GPS jitter while parked; keep the old anchor so slow creeping still adds up.
            if d < max(4, location.horizontalAccuracy * 0.5) { return }
            // Stopped at a light: wander within the error circle isn't driving.
            if location.speed >= 0, location.speed < 0.7, d < max(15, location.horizontalAccuracy) { return }
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

    private func geocode(_ location: CLLocation, isStart: Bool, driveID: UUID) {
        Task { [weak self] in
            // One geocoder per request so a quick stop doesn't cancel the start lookup.
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first, let self else { return }
            let parts = [placemark.thoroughfare, placemark.locality].compactMap { $0 }
            let name = parts.isEmpty ? placemark.name : parts.joined(separator: ", ")
            guard let name, var a = self.activeDrive, a.id == driveID else { return }
            if isStart { a.startPlaceName = name } else { a.endPlaceName = name }
            self.activeDrive = a
            self.persistActive(force: true)
        }
    }

    private func persistActive(force: Bool) {
        guard let a = activeDrive, !writesBlocked else { return }
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
        // Drivers in the backup that this phone doesn't know yet.
        let known = Set(settings.allDrivers.map(\.id))
        for profile in archive.settings.allDrivers where !known.contains(profile.id) && !restoreSettings {
            if archive.drives.contains(where: { $0.driverID == profile.id }) { settings.otherDrivers.append(profile) }
        }
        for var incoming in archive.drives {
            // Old backups have no driver: they belong to whoever is active.
            if incoming.driverID == nil { incoming.driverID = restoreSettings ? archive.settings.activeDriverID : settings.activeDriverID }
            if let i = allDrives.firstIndex(where: { $0.id == incoming.id }) {
                if incoming.modifiedAt > allDrives[i].modifiedAt {
                    // Keep the route if the backup copy (e.g. from Notes) doesn't carry one.
                    var merged = incoming
                    if merged.route.isEmpty { merged.route = allDrives[i].route }
                    allDrives[i] = merged
                    summary.updated += 1
                } else {
                    summary.unchanged += 1
                }
            } else {
                allDrives.append(incoming)
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
            // Keep this phone's drivers that have drives, so none of their hours disappear from view.
            let incomingIDs = Set(s.allDrivers.map(\.id))
            for p in settings.allDrivers where !incomingIDs.contains(p.id) && allDrives.contains(where: { $0.driverID == p.id }) {
                s.otherDrivers.append(p)
            }
            settings = s
        } else {
            settings.supervisors = merge(settings.supervisors, archive.settings.supervisors)
            settings.vehicles = merge(settings.vehicles, archive.settings.vehicles)
            if !archive.drives.isEmpty { settings.hasOnboarded = true }
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
        LogArchive(settings: settings, drives: allDrives, recentlyDeleted: recentlyDeleted)
    }

    /// Drives added or edited since the last backup that left the device.
    /// The newest copy known to have left the phone: a shared/Notes backup or the iCloud Drive folder.
    var lastOffDeviceBackup: Date? {
        let cloud = cloudFolder?.isInICloud == true ? cloudFolder?.lastBackup : nil
        switch (settings.lastExternalBackup, cloud) {
        case let (a?, b?): return max(a, b)
        case let (a, b): return a ?? b
        }
    }

    var changesSinceExternalBackup: Int {
        guard let last = lastOffDeviceBackup else { return allDrives.count }
        return allDrives.filter { $0.modifiedAt > last }.count
    }

    func markExternalBackup(toNotes: Bool) {
        settings.lastExternalBackup = Date()
        if toNotes { settings.lastNotesBackup = Date() }
        saveNow()
    }

    // MARK: - Drivers

    /// Switches every screen, goal and export to another driver.
    func switchDriver(to id: UUID) {
        guard id != settings.activeDriverID, activeDrive == nil,
              let target = settings.otherDrivers.first(where: { $0.id == id }) else { return }
        var s = settings
        s.otherDrivers.removeAll { $0.id == id }
        s.otherDrivers.append(s.activeProfile)
        s.activeProfile = target
        settings = s
        saveNow()
    }

    func addDriver(named name: String) {
        var profile = settings.activeProfile
        profile.id = UUID()
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.permitNumber = ""
        profile.permitIssued = nil
        settings.otherDrivers.append(profile)
        switchDriver(to: profile.id)
    }

    /// Only drivers with no drives (including in Recently Deleted) can be removed, so no hours are lost.
    func canRemoveDriver(_ id: UUID) -> Bool {
        settings.allDrivers.count > 1
            && !allDrives.contains { $0.driverID == id }
            && !recentlyDeleted.contains { $0.drive.driverID == id }
    }

    func removeDriver(_ id: UUID) {
        guard canRemoveDriver(id) else { return }
        if id == settings.activeDriverID, let next = settings.otherDrivers.first {
            switchDriver(to: next.id)
        }
        settings.otherDrivers.removeAll { $0.id == id }
        saveNow()
    }

    // MARK: - iCloud Drive folder

    func setCloudFolder(_ url: URL) throws {
        cloudFolder = try CloudFolderBackup.makeState(for: url)
        CloudFolderBackup.saveState(cloudFolder)
        backUpToCloudFolder()
    }

    func removeCloudFolder() {
        cloudFolder = nil
        CloudFolderBackup.saveState(nil)
    }

    /// Copies the log, PDF and text into the chosen folder. Safe to call often; overlapping calls coalesce.
    func backUpToCloudFolder(pdf: Data? = nil, text: Data? = nil) {
        guard let folder = cloudFolder, !writesBlocked else { return }
        if isWritingCloudFolder { cloudWritePending = true; return }
        guard let json = try? BackupCodec.encode(archive, pretty: true) else { return }
        let payload = CloudFolderBackup.Payload(
            archiveJSON: json,
            pdf: pdf ?? PDFLogRenderer.render(drives: drives, settings: settings, stats: stats),
            text: text ?? TextLogFormatter.notesBackup(drives: drives, settings: settings, archive: archive).data(using: .utf8)
        )
        isWritingCloudFolder = true
        Task { [weak self] in
            var result = folder
            do {
                if let refreshed = try await CloudFolderBackup.write(payload, bookmark: folder.bookmark) {
                    result.bookmark = refreshed
                }
                result.lastBackup = Date()
                result.lastError = nil
            } catch {
                result.lastError = "Couldn't save to \(folder.folderName): \(error.localizedDescription). Choose the folder again in Backup & Export."
            }
            guard let self else { return }
            // Ignore the result if the folder was changed or removed while writing.
            if self.cloudFolder?.bookmark == folder.bookmark {
                self.cloudFolder = result
                CloudFolderBackup.saveState(result)
            }
            self.isWritingCloudFolder = false
            if self.cloudWritePending {
                self.cloudWritePending = false
                self.backUpToCloudFolder()
            }
        }
    }

    /// False while the log file couldn't be read; nothing is saved until it can be.
    var isLogAvailable: Bool { !writesBlocked }

    /// Call when the app comes to the foreground (and before Shortcuts actions): retries a log that
    /// couldn't be read at launch (e.g. the phone was still locked) and resumes GPS for a live drive.
    func becameActive() {
        if writesBlocked {
            writesBlocked = false
            loadWarning = nil
            lastSaveError = nil
            load()
        }
        if let a = activeDrive, a.stoppedAt == nil, settings.trackLocation {
            tracker.start()
        }
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

    @discardableResult
    private func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard !writesBlocked else {
            lastSaveError = "Your log couldn't be opened, so changes aren't being saved to protect it. Close and reopen the app."
            return false
        }
        var ok = false
        do {
            let data = try BackupCodec.encode(archive)
            let primary = StorePaths.primaryLog
            if fm.fileExists(atPath: primary.path) {
                try? fm.removeItem(at: StorePaths.previousLog)
                try? fm.copyItem(at: primary, to: StorePaths.previousLog)
            }
            try data.write(to: primary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastSaveError = nil
            ok = true
        } catch {
            lastSaveError = "Couldn't save your log: \(error.localizedDescription)"
        }
        scheduleExports()
        return ok
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
        let pdf = PDFLogRenderer.render(drives: drives, settings: settings, stats: stats)
        if let pdf { try? pdf.write(to: StorePaths.documentsPDF, options: .atomic) }
        let text = TextLogFormatter.notesBackup(drives: drives, settings: settings, archive: archive).data(using: .utf8)
        try? text?.write(to: StorePaths.documentsText, options: .atomic)
        backUpToCloudFolder(pdf: pdf, text: text)
    }

    func writeSnapshot(suffix: String?) {
        guard !writesBlocked, !allDrives.isEmpty || !recentlyDeleted.isEmpty else { return }
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
        var migratedDrivers = false
        var damaged: LogArchive?

        if fm.fileExists(atPath: primary.path) {
            do {
                let data = try Data(contentsOf: primary)
                do {
                    loaded = try BackupCodec.decode(data)
                } catch {
                    // Damaged file: keep a copy, rescue whatever drives can still be read, then fall back
                    // to the backups below and merge the rescued drives in.
                    damaged = try? BackupCodec.decodeForRestore(data)
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
            var rescued = 0
            if let damaged {
                if loaded == nil {
                    loaded = damaged
                    recoveredFrom = "the readable part of your log"
                } else if var base = loaded {
                    for d in damaged.drives {
                        if let i = base.drives.firstIndex(where: { $0.id == d.id }) {
                            if d.modifiedAt > base.drives[i].modifiedAt { base.drives[i] = d }
                        } else {
                            base.drives.append(d)
                            base.recentlyDeleted.removeAll { $0.id == d.id }
                            rescued += 1
                        }
                    }
                    loaded = base
                }
            }
            if fm.fileExists(atPath: primary.path) {
                let lost = damaged?.skippedDrives ?? 0
                let extra = (rescued > 0 ? " \(rescued) newer drive\(rescued == 1 ? " was" : "s were") rescued from the damaged file." : "")
                    + (lost > 0 ? " \(lost) drive\(lost == 1 ? "" : "s") couldn't be read." : "")
                loadWarning = recoveredFrom != nil
                    ? "Your log file was damaged, so it was recovered from \(recoveredFrom ?? "a backup").\(extra) Check that your latest drives are there; if not, use Settings ▸ Restore with your Notes backup."
                    : "Your log file was damaged and no automatic backup could be read. Use Settings ▸ Restore with your Notes backup."
            }
        }

        if let loaded {
            settings = loaded.settings
            allDrives = loaded.drives.sorted { $0.startDate > $1.startDate }
            // Drives from before multiple drivers existed (or whose driver is unknown) go to the active driver,
            // so no drive is ever hidden.
            let known = Set(settings.allDrivers.map(\.id))
            for i in allDrives.indices where allDrives[i].driverID.map({ !known.contains($0) }) ?? true {
                allDrives[i].driverID = settings.activeDriverID
                migratedDrivers = true
            }
            let cutoff = Calendar.current.date(byAdding: .day, value: -Self.trashRetentionDays, to: Date()) ?? .distantPast
            recentlyDeleted = loaded.recentlyDeleted.filter { $0.deletedAt > cutoff }
            for i in recentlyDeleted.indices where recentlyDeleted[i].drive.driverID.map({ !known.contains($0) }) ?? true {
                recentlyDeleted[i].drive.driverID = settings.activeDriverID
                migratedDrivers = true
            }
        }

        if let data = try? Data(contentsOf: StorePaths.activeDrive),
           let a = try? BackupCodec.makeDecoder().decode(ActiveDrive.self, from: data) {
            activeDrive = a
        }

        if recoveredFrom != nil || migratedDrivers {
            // Re-create the primary file from the recovered copy (or save the driver migration).
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
