import AppIntents
import Foundation

/// Returns the full log as text (with restore data). Pair it with the Notes "Create Note" action in a
/// Shortcuts automation to back up to Notes on a schedule with no taps.
struct GetDrivingLogBackupIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Driving Log Backup"
    static var description = IntentDescription(
        "Returns your whole TrackMyDrive log as text, including the restore data. Send it to the Notes “Create Note” action to keep an automatic backup."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = DriveStore.shared
        store.becameActive()
        // Never hand back an empty log (which could replace a good note) when the real one can't be read.
        guard store.isLogAvailable else { throw LogUnavailableError() }
        store.markExternalBackup(toNotes: false)
        return .result(value: ExportService.notesText(store: store))
    }
}

struct LogUnavailableError: LocalizedError {
    var errorDescription: String? {
        "TrackMyDrive couldn't open your log right now (the phone may be locked). No backup was made — try again after unlocking."
    }
}

struct DrivingHoursSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Driving Hours Summary"
    static var description = IntentDescription("Tells you how many hours you've logged and how many are left.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        DriveStore.shared.becameActive()
        let stats = DriveStore.shared.stats
        var text = "You've logged \(Fmt.duration(minutes: stats.totalMinutes)), including \(Fmt.duration(minutes: stats.nightMinutes)) at night."
        if stats.goalsComplete {
            text += " You've met your goals!"
        } else {
            text += " \(Fmt.duration(minutes: stats.totalRemainingMinutes)) to go"
            text += stats.nightRemainingMinutes > 0 ? ", with \(Fmt.duration(minutes: stats.nightRemainingMinutes)) of night driving left." : "."
        }
        return .result(value: text, dialog: "\(text)")
    }
}

struct StartDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Drive"
    static var description = IntentDescription("Starts timing a supervised drive.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = DriveStore.shared
        store.becameActive()
        if let active = store.activeDrive {
            return .result(dialog: active.stoppedAt == nil
                ? "A drive is already in progress."
                : "Your last drive is waiting to be saved. Open TrackMyDrive to save it first.")
        }
        store.startDrive(supervisor: store.settings.defaultSupervisor, vehicle: store.settings.defaultVehicle)
        return .result(dialog: "Drive started. Drive safely!")
    }
}

struct StopDriveIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Drive"
    static var description = IntentDescription("Stops the current drive so you can review and save it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = DriveStore.shared
        store.becameActive()
        guard let active = store.activeDrive, active.stoppedAt == nil else {
            return .result(dialog: "There's no drive in progress.")
        }
        store.stopDrive()
        return .result(dialog: "Drive stopped. Review it in TrackMyDrive to save it.")
    }
}

struct TrackMyDriveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDriveIntent(),
            phrases: ["Start a drive in \(.applicationName)", "Start driving with \(.applicationName)"],
            shortTitle: "Start Drive",
            systemImageName: "steeringwheel"
        )
        AppShortcut(
            intent: StopDriveIntent(),
            phrases: ["Stop my drive in \(.applicationName)", "End drive in \(.applicationName)"],
            shortTitle: "Stop Drive",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: DrivingHoursSummaryIntent(),
            phrases: ["How many hours do I have in \(.applicationName)", "\(.applicationName) hours"],
            shortTitle: "Hours Summary",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: GetDrivingLogBackupIntent(),
            phrases: ["Back up my \(.applicationName) log"],
            shortTitle: "Backup Text",
            systemImageName: "doc.text"
        )
    }
}
