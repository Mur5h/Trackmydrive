import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case home, log, stats, settings }

    @EnvironmentObject private var store: DriveStore
    @State private var selectedTab: Tab = .home
    /// Lets the user hide the live-drive screen (e.g. to check the log) without stopping the drive.
    @State private var activeMinimized = false

    private var showActiveDrive: Binding<Bool> {
        Binding(
            get: { store.activeDrive != nil && !activeMinimized && store.settings.hasOnboarded },
            set: { if !$0 { activeMinimized = true } }
        )
    }

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !store.settings.hasOnboarded }, set: { _ in })
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab, openActiveDrive: openActiveDrive)
                .activeDriveBar(open: openActiveDrive, hidden: !activeMinimized)
                .tabItem { Label("Home", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(Tab.home)
            LogView()
                .activeDriveBar(open: openActiveDrive, hidden: !activeMinimized)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle.portrait") }
                .tag(Tab.log)
            StatsView()
                .activeDriveBar(open: openActiveDrive, hidden: !activeMinimized)
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                .tag(Tab.stats)
            SettingsView()
                .activeDriveBar(open: openActiveDrive, hidden: !activeMinimized)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .fullScreenCover(isPresented: showActiveDrive) {
            ActiveDriveView(minimize: { activeMinimized = true })
                .environmentObject(store)
                .environmentObject(LocationTracker.shared)
        }
        .fullScreenCover(isPresented: showOnboarding) {
            OnboardingView()
                .environmentObject(store)
                .environmentObject(LocationTracker.shared)
        }
        .onChange(of: store.activeDrive?.id) { _, newID in
            // A new drive (or a finished one) always starts with the live screen un-minimized.
            if newID == nil { activeMinimized = false }
        }
        .onChange(of: store.activeDrive?.stoppedAt) { _, stopped in
            // Stopping from Siri/Shortcuts should bring up the review screen.
            if stopped != nil { activeMinimized = false }
        }
        .onChange(of: store.settings.reminderEnabled) { _, _ in syncReminders() }
        .onChange(of: store.settings.reminderMinutes) { _, _ in syncReminders() }
        .onChange(of: store.drives.count) { _, _ in syncReminders() }
        .onAppear(perform: syncReminders)
    }

    private func openActiveDrive() {
        activeMinimized = false
    }

    private func syncReminders() {
        NotificationService.sync(with: store.settings, stats: store.stats)
    }
}

private struct ActiveDriveBar: ViewModifier {
    @EnvironmentObject private var store: DriveStore
    let open: () -> Void
    let hidden: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let active = store.activeDrive, !hidden {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Image(systemName: active.stoppedAt == nil ? "car.fill" : "checkmark.circle.fill")
                            .symbolEffect(.pulse, isActive: active.stoppedAt == nil)
                        Text(active.stoppedAt == nil ? "Drive in progress" : "Tap to save your drive")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(Fmt.clock(seconds: active.elapsed(at: ctx.date)))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        Image(systemName: "chevron.up")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.brandGradient, in: Capsule())
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

private extension View {
    func activeDriveBar(open: @escaping () -> Void, hidden: Bool) -> some View {
        modifier(ActiveDriveBar(open: open, hidden: hidden))
    }
}
