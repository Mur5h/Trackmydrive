import SwiftUI

@main
struct TrackMyDriveApp: App {
    @StateObject private var store = DriveStore.shared
    @StateObject private var location = LocationTracker.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                // scenePhase doesn't change on a cold launch, so run the foreground work once here too.
                .onAppear { store.becameActive() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.becameActive() } else { store.flush() }
        }
    }
}
