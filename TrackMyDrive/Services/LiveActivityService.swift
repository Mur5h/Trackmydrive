import ActivityKit
import Foundation

/// Keeps the lock-screen Live Activity in step with the drive: started with the drive, switched to
/// "stopped" when it ends, removed once the drive is saved or discarded.
@MainActor
enum LiveActivityService {
    static func sync(with active: ActiveDrive?, driverName: String) {
        let activities = Activity<DriveActivityAttributes>.activities
        guard let active else {
            for activity in activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let state = DriveActivityAttributes.ContentState(startDate: active.startDate, stoppedAt: active.stoppedAt,
                                                         supervisor: active.supervisor)
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activities.first {
            Task { await current.update(content) }
            for extra in activities.dropFirst() {
                Task { await extra.end(nil, dismissalPolicy: .immediate) }
            }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // Only possible while the app is in the foreground; becameActive() retries.
            _ = try? Activity.request(attributes: DriveActivityAttributes(driverName: driverName), content: content)
        }
    }
}
