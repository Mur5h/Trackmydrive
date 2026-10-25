import Foundation
import UserNotifications
import UIKit

enum NotificationService {
    private static let practiceID = "daily-practice-reminder"
    private static let stillDrivingIDs = ["still-driving-3h", "still-driving-6h"]

    /// Reminders in case the drive was never stopped. Rescheduled from the drive's start time.
    static func scheduleStillDriving(startedAt start: Date) {
        Task {
            guard await requestAuthorization() else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: stillDrivingIDs)
            for (id, hours) in zip(stillDrivingIDs, [3.0, 6.0]) {
                let fire = start.addingTimeInterval(hours * 3600)
                let delay = fire.timeIntervalSinceNow
                guard delay > 1 else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Still driving?"
                content.body = "Your drive has been running for \(Int(hours)) hours. If you forgot to stop it, open TrackMyDrive to end it at the right time."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    static func cancelStillDriving() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stillDrivingIDs)
    }

    /// Asks for permission if needed. Returns whether notifications are allowed.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Schedules (or removes) the daily practice reminder to match the settings.
    static func sync(with settings: AppSettings, stats: LogStats) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [practiceID])
        guard settings.reminderEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for a practice drive?"
        if stats.goalsComplete {
            content.body = "You've hit your goals — keep your skills sharp with a quick drive."
        } else {
            content.body = "\(Fmt.duration(minutes: stats.totalRemainingMinutes)) to go"
                + (stats.nightRemainingMinutes > 0 ? ", including \(Fmt.duration(minutes: stats.nightRemainingMinutes)) at night." : ".")
        }
        content.sound = .default

        var comps = DateComponents()
        comps.hour = settings.reminderMinutes / 60
        comps.minute = settings.reminderMinutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: practiceID, content: content, trigger: trigger))
    }
}

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}
