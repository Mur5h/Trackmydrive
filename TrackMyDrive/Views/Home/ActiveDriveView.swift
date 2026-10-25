import SwiftUI
import UIKit

struct ActiveDriveView: View {
    @EnvironmentObject private var store: DriveStore
    @EnvironmentObject private var location: LocationTracker
    var minimize: () -> Void

    @State private var confirmStop = false
    @State private var confirmDiscard = false
    @State private var editingSupervisor = false

    var body: some View {
        Group {
            if let active = store.activeDrive {
                if active.stoppedAt == nil {
                    liveView(active)
                } else if let draft = store.draftFromActiveDrive() {
                    DriveEditorView(mode: .review(draft))
                }
            } else {
                Color.clear
            }
        }
        .onAppear(perform: updateIdleTimer)
        .onChange(of: store.activeDrive?.stoppedAt) { _, _ in updateIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func updateIdleTimer() {
        let driving = store.activeDrive != nil && store.activeDrive?.stoppedAt == nil
        UIApplication.shared.isIdleTimerDisabled = driving && store.settings.keepScreenOnWhileDriving
    }

    // MARK: Live

    private func liveView(_ active: ActiveDrive) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isNight = NightCalculator.isNight(at: context.date, latitude: active.lastLatitude ?? active.startLatitude,
                                                  longitude: active.lastLongitude ?? active.startLongitude, settings: store.settings)
            let nightSoFar = NightCalculator.nightMinutes(start: active.startDate, end: context.date,
                                                          latitude: active.startLatitude, longitude: active.startLongitude,
                                                          settings: store.settings)
            ZStack {
                (isNight ? Theme.nightGradient : Theme.dayGradient)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 1), value: isNight)

                VStack(spacing: 0) {
                    topBar(isNight: isNight)

                    // Scrolls on small phones and large text sizes; Stop stays pinned below.
                    ScrollView {
                        VStack(spacing: 0) {
                            VStack(spacing: 6) {
                                Text("DRIVE TIME")
                                    .font(.caption.weight(.bold))
                                    .tracking(2)
                                    .opacity(0.8)
                                Text(Fmt.clock(seconds: active.elapsed(at: context.date)))
                                    .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
                                    .minimumScaleFactor(0.4)
                                    .lineLimit(1)
                                    .contentTransition(.numericText())
                                Text("Started \(Fmt.time.string(from: active.startDate))")
                                    .font(.subheadline)
                                    .opacity(0.85)
                            }
                            .accessibilityElement(children: .combine)
                            .padding(.vertical, 28)

                            // No speedometer on purpose: nothing here should be worth a glance from the driver.
                            HStack(spacing: 12) {
                                liveStat(title: "Distance", value: trackingAvailable ? Fmt.distance(meters: active.distanceMeters, unit: store.settings.distanceUnit) : "—",
                                         symbol: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                liveStat(title: "Night", value: Fmt.duration(minutes: nightSoFar), symbol: "moon.stars.fill")
                            }
                            .padding(.horizontal)

                            supervisorCard(active)
                                .padding(.horizontal)
                                .padding(.top, 12)

                            locationNotice
                                .padding(.horizontal)
                                .padding(.top, 10)
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 10) {
                        stopButton
                        Label("Driver: eyes on the road. Only the supervisor uses the phone.", systemImage: "hand.raised.fill")
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
            }
            .foregroundStyle(.white)
        }
        .confirmationDialog("End this drive?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("End Drive") {
                Haptics.success()
                store.stopDrive()
            }
            Button("Keep Driving", role: .cancel) {}
        } message: {
            Text("You'll be able to add conditions and notes before saving.")
        }
        .confirmationDialog("Discard this drive?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Drive", role: .destructive) {
                Haptics.warning()
                store.discardActiveDrive()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The time from this drive won't be logged. This can't be undone.")
        }
        .sheet(isPresented: $editingSupervisor) {
            ActiveDriveDetailsSheet()
                .presentationDetents([.medium])
        }
    }

    private var trackingAvailable: Bool {
        store.settings.trackLocation && location.isAuthorized && location.isPrecise
    }

    private func topBar(isNight: Bool) -> some View {
        HStack {
            Button(action: minimize) {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Minimize")
            Spacer()
            Label(isNight ? "Night driving" : "Day driving", systemImage: isNight ? "moon.fill" : "sun.max.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.15), in: Capsule())
            Spacer()
            Menu {
                Button("Discard Drive", systemImage: "trash", role: .destructive) { confirmDiscard = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func liveStat(title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.headline).opacity(0.8)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title.uppercased()).font(.caption2.weight(.semibold)).opacity(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func supervisorCard(_ active: ActiveDrive) -> some View {
        Button { editingSupervisor = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.fill.checkmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Supervisor").font(.caption).opacity(0.7)
                    Text(active.supervisor.isEmpty ? "Add supervisor" : active.supervisor)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if !active.vehicle.isEmpty {
                    Text(active.vehicle).font(.caption).opacity(0.75).lineLimit(1)
                }
                Image(systemName: "pencil").opacity(0.7)
            }
            .padding(12)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var locationNotice: some View {
        if store.settings.trackLocation && location.isAuthorized && !location.isPrecise {
            HStack(spacing: 10) {
                Image(systemName: "location.circle")
                Text("Precise Location is off, so distance can't be measured.")
                    .font(.footnote)
                Spacer()
                Button("Turn On") { location.requestPreciseLocation() }
                    .font(.footnote.weight(.semibold))
            }
            .padding(12)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        if store.settings.trackLocation && location.isDenied {
            HStack(spacing: 10) {
                Image(systemName: "location.slash.fill")
                Text("Location is off, so only time is recorded.")
                    .font(.footnote)
                Spacer()
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(12)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var stopButton: some View {
        Button {
            Haptics.tap()
            confirmStop = true
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.15)).frame(width: 112, height: 112)
                Circle().fill(Color.red).frame(width: 88, height: 88)
                    .shadow(color: .red.opacity(0.5), radius: 16, y: 6)
                RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End drive")
    }
}

/// Change the supervisor or vehicle mid-drive.
private struct ActiveDriveDetailsSheet: View {
    @EnvironmentObject private var store: DriveStore
    @Environment(\.dismiss) private var dismiss
    @State private var supervisor = ""
    @State private var vehicle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Supervisor") {
                    NameField(placeholder: "Supervisor name", text: $supervisor, options: store.settings.supervisorOptions)
                }
                Section("Vehicle") {
                    NameField(placeholder: "Vehicle (optional)", text: $vehicle, options: store.settings.vehicleOptions)
                }
            }
            .navigationTitle("Drive Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.updateActive(supervisor: supervisor.trimmingCharacters(in: .whitespacesAndNewlines),
                                           vehicle: vehicle.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
            .onAppear {
                supervisor = store.activeDrive?.supervisor ?? ""
                vehicle = store.activeDrive?.vehicle ?? ""
            }
        }
    }
}

/// Text field with a menu of previously used names.
struct NameField: View {
    let placeholder: String
    @Binding var text: String
    let options: [String]

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !options.isEmpty {
                Menu {
                    ForEach(options, id: \.self) { name in
                        Button(name) { text = name }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title3)
                }
                .accessibilityLabel("Choose a saved name")
            }
        }
    }
}
