import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TrackMyDriveWidgets: WidgetBundle {
    var body: some Widget {
        DriveLiveActivity()
    }
}

/// Lock screen + Dynamic Island for a drive in progress: a running timer and a Stop button,
/// so the supervisor never has to unlock the phone and dig into the app.
struct DriveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            LockScreenDriveView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(red: 0.08, green: 0.20, blue: 0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Drive", systemImage: "steeringwheel")
                        .font(.headline)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.stoppedAt == nil {
                        StopButton()
                    } else {
                        Text("Stopped — open TrackMyDrive to save").font(.subheadline)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.stoppedAt == nil ? "steeringwheel" : "checkmark.circle.fill")
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "steeringwheel")
            }
        }
    }
}

private struct LockScreenDriveView: View {
    let attributes: DriveActivityAttributes
    let state: DriveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.stoppedAt == nil ? "Driving" : "Drive stopped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                ElapsedText(state: state)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if state.stoppedAt == nil {
                StopButton()
            } else {
                Text("Open to save")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !attributes.driverName.isEmpty { parts.append(attributes.driverName) }
        if !state.supervisor.isEmpty { parts.append("with \(state.supervisor)") }
        return parts.isEmpty ? "Supervised drive" : parts.joined(separator: " ")
    }
}

/// Counts up live while driving; frozen at the final time once stopped.
private struct ElapsedText: View {
    let state: DriveActivityAttributes.ContentState

    var body: some View {
        if let stopped = state.stoppedAt {
            Text(Self.format(stopped.timeIntervalSince(state.startDate)))
        } else {
            Text(timerInterval: state.startDate...Date.distantFuture, countsDown: false)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct StopButton: View {
    var body: some View {
        Button(intent: StopDriveFromActivityIntent()) {
            Label("Stop", systemImage: "stop.fill")
                .font(.headline)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.red)
    }
}
