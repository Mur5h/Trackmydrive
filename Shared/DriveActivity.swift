import ActivityKit
import AppIntents
import Foundation

/// Data for the lock-screen / Dynamic Island Live Activity shown while a drive is running.
/// Compiled into both the app and the widget extension.
struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        /// Set once the drive is stopped and waiting to be saved.
        var stoppedAt: Date?
        var supervisor: String
    }

    var driverName: String
}

/// The Stop button on the Live Activity. It always runs inside the app's process.
struct StopDriveFromActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Drive"
    static var description = IntentDescription("Stops the drive in progress so it can be reviewed and saved.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { DriveStore.shared.stopDrive() }
        #endif
        return .result()
    }
}
