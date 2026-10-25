import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: DriveStore
    @EnvironmentObject private var location: LocationTracker
    @State private var recalcMessage: String?
    @State private var confirmRecalc = false
    @State private var confirmDeleteAll = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                driverSection
                goalsSection
                nightSection
                defaultsSection
                remindersSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .alert("Night Time Updated", isPresented: Binding(get: { recalcMessage != nil }, set: { if !$0 { recalcMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recalcMessage ?? "")
            }
            .alert("Notifications Are Off", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Allow notifications for TrackMyDrive in the Settings app to get practice reminders.")
            }
            .confirmationDialog("Delete all drives?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All \(store.drives.count) Drives", role: .destructive) { store.deleteAll() }
            } message: {
                Text("They'll move to Recently Deleted for \(DriveStore.trashRetentionDays) days before being removed.")
            }
        }
    }

    // MARK: Sections

    private var driverSection: some View {
        Section("Driver") {
            LabeledContent("Name") {
                TextField("Your name", text: $store.settings.studentName)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.name)
            }
            LabeledContent("Permit #") {
                TextField("Optional", text: $store.settings.permitNumber)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
            }
        }
    }

    private var goalsSection: some View {
        Section {
            Picker("State", selection: stateBinding) {
                Text("Custom").tag("")
                ForEach(StatePreset.all) { preset in
                    Text(preset.name).tag(preset.code)
                }
            }
            Stepper(value: $store.settings.totalGoalHours, in: 1...200, step: 1) {
                LabeledContent("Total hours", value: "\(Int(store.settings.totalGoalHours))")
            }
            Stepper(value: $store.settings.nightGoalHours, in: 0...100, step: 1) {
                LabeledContent("Night hours", value: "\(Int(store.settings.nightGoalHours))")
            }
        } header: {
            Text("Requirements")
        } footer: {
            Text("State presets are common figures only and rules change. Always confirm your exact requirements with your DMV.")
        }
    }

    private var stateBinding: Binding<String> {
        Binding(
            get: { store.settings.stateCode },
            set: { code in
                store.settings.stateCode = code
                if let preset = StatePreset.all.first(where: { $0.code == code }) {
                    store.settings.totalGoalHours = preset.totalHours
                    store.settings.nightGoalHours = preset.nightHours
                }
            }
        )
    }

    private var nightSection: some View {
        Section {
            Picker("Night is", selection: $store.settings.nightMode) {
                ForEach(NightMode.allCases) { Text($0.label).tag($0) }
            }
            if store.settings.nightMode == .sunsetToSunrise {
                Picker("Starts", selection: $store.settings.nightOffsetMinutes) {
                    Text("At sunset").tag(0)
                    Text("15 min after sunset").tag(15)
                    Text("30 min after sunset").tag(30)
                    Text("1 hr after sunset").tag(60)
                }
            }
            if store.settings.nightMode == .fixedHours || store.settings.lastKnownLatitude == nil {
                DatePicker(store.settings.nightMode == .fixedHours ? "From" : "Fallback from",
                           selection: minutesBinding(\.fixedNightStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker(store.settings.nightMode == .fixedHours ? "Until" : "Fallback until",
                           selection: minutesBinding(\.fixedNightEndMinutes), displayedComponents: .hourAndMinute)
            }
            Button("Recalculate Night Time for All Drives") { confirmRecalc = true }
                .confirmationDialog("Recalculate night time for every drive?", isPresented: $confirmRecalc, titleVisibility: .visible) {
                    Button("Recalculate") {
                        let n = store.recalculateNightTimes()
                        recalcMessage = n == 0 ? "All drives were already up to date." : "Updated \(n) drive\(n == 1 ? "" : "s"). Drives with night time entered by hand weren't changed. A copy of your log from before this change was saved in Files ▸ TrackMyDrive ▸ Backups."
                    }
                } message: {
                    Text("Night time on every drive will be worked out again using your current night settings. Drives where you typed the night time yourself won't change. A backup copy is saved first.")
                }
        } header: {
            Text("Night Driving")
        } footer: {
            Text(store.settings.nightMode == .sunsetToSunrise
                 ? "Sunset and sunrise are calculated for where each drive starts. Drives without a location use your last known location, or the fallback hours."
                 : "Any driving between these times counts as night.")
        }
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = store.settings[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private var defaultsSection: some View {
        Section {
            NavigationLink {
                NamesListView(title: "Supervisors", names: $store.settings.supervisors, defaultName: $store.settings.defaultSupervisor)
            } label: {
                LabeledContent("Supervisors", value: store.settings.defaultSupervisor.isEmpty ? "\(store.settings.supervisors.count)" : store.settings.defaultSupervisor)
            }
            NavigationLink {
                NamesListView(title: "Vehicles", names: $store.settings.vehicles, defaultName: $store.settings.defaultVehicle)
            } label: {
                LabeledContent("Vehicles", value: store.settings.defaultVehicle.isEmpty ? "\(store.settings.vehicles.count)" : store.settings.defaultVehicle)
            }
            Picker("Distance", selection: $store.settings.distanceUnit) {
                ForEach(DistanceUnit.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Track Distance & Route", isOn: $store.settings.trackLocation)
            if store.settings.trackLocation && location.isDenied {
                Button("Location access is off — open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.footnote)
            }
            Toggle("Keep Screen On While Driving", isOn: $store.settings.keepScreenOnWhileDriving)
        } header: {
            Text("Drives")
        } footer: {
            Text("Location is only used while a drive is running and never leaves your phone.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Daily Practice Reminder", isOn: reminderBinding)
            if store.settings.reminderEnabled {
                DatePicker("Time", selection: minutesBinding(\.reminderMinutes), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { store.settings.reminderEnabled },
            set: { on in
                guard on else { store.settings.reminderEnabled = false; return }
                Task {
                    let allowed = await NotificationService.requestAuthorization()
                    store.settings.reminderEnabled = allowed
                    if !allowed { notificationsDenied = true }
                }
            }
        )
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                BackupView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup & Export")
                        Text(store.lastOffDeviceBackup.map { "Last backup \(Fmt.relative($0))" } ?? "Not backed up yet")
                            .font(.caption)
                            .foregroundStyle(store.changesSinceExternalBackup > 0 ? Color.orange : Color.secondary)
                    }
                } icon: {
                    Image(systemName: "externaldrive.fill.badge.icloud").foregroundStyle(Color.accentColor)
                }
            }
            NavigationLink {
                RestoreView()
            } label: {
                Label("Restore From Backup", systemImage: "arrow.counterclockwise.icloud")
            }
            NavigationLink {
                RecentlyDeletedView()
            } label: {
                LabeledContent {
                    Text("\(store.recentlyDeleted.count)")
                } label: {
                    Label("Recently Deleted", systemImage: "trash")
                }
            }
            if !store.drives.isEmpty {
                Button("Delete All Drives", role: .destructive) { confirmDeleteAll = true }
            }
        } header: {
            Text("Your Data")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            LabeledContent("Drives logged", value: "\(store.drives.count)")
        } header: {
            Text("About")
        } footer: {
            Text("TrackMyDrive helps you keep an accurate log. Never use your phone while driving — let your supervisor handle the app.")
        }
    }
}

/// Editable list of saved names with a default.
struct NamesListView: View {
    let title: String
    @Binding var names: [String]
    @Binding var defaultName: String
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add \(String(title.lowercased().dropLast()))", text: $newName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                ForEach(names, id: \.self) { name in
                    Button {
                        defaultName = defaultName == name ? "" : name
                    } label: {
                        HStack {
                            Text(name).foregroundStyle(.primary)
                            Spacer()
                            if defaultName == name {
                                Text("Default").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { names[$0] }
                    names.remove(atOffsets: offsets)
                    if removed.contains(defaultName) { defaultName = "" }
                }
            } footer: {
                Text(names.isEmpty ? "Names you use on drives are saved here automatically." : "Tap a name to make it the default for new drives. Swipe to remove.")
            }
        }
        .navigationTitle(title)
        .toolbar { if !names.isEmpty { EditButton() } }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !names.contains(name) { names.append(name) }
        if defaultName.isEmpty { defaultName = name }
        newName = ""
    }
}
