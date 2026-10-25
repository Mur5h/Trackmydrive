import SwiftUI
import MapKit

struct DriveEditorView: View {
    enum Mode {
        case new
        case edit(Drive)
        /// Reviewing a just-finished live drive.
        case review(Drive)
    }

    @EnvironmentObject private var store: DriveStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    @State private var draft: Drive
    @State private var manualNight: Bool
    @State private var manualNightMinutes: Double
    @State private var distanceText: String
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var showLongDriveWarning = false
    @State private var didAppear = false
    @State private var saveFailed = false
    @FocusState private var focusedField: Field?

    private enum Field { case distance, notes }

    init(mode: Mode) {
        self.mode = mode
        let initial: Drive
        switch mode {
        case .new:
            let end = Self.roundedToFiveMinutes(Date())
            initial = Drive(startDate: end.addingTimeInterval(-30 * 60), endDate: end)
        case .edit(let d), .review(let d):
            initial = d
        }
        _draft = State(initialValue: initial)
        _manualNight = State(initialValue: initial.nightMinutesIsManual)
        _manualNightMinutes = State(initialValue: initial.nightMinutes.rounded())
        _distanceText = State(initialValue: "")
    }

    private var isReview: Bool { if case .review = mode { return true } else { return false } }
    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }

    private var title: String {
        switch mode {
        case .new: return "Log a Drive"
        case .edit: return "Edit Drive"
        case .review: return "Save Your Drive"
        }
    }

    private var autoNightMinutes: Double { store.computedNightMinutes(for: draft) }

    private var validationError: String? {
        if draft.endDate <= draft.startDate { return "The end time must be after the start time." }
        if draft.duration > 24 * 3600 { return "A single drive can't be longer than 24 hours. Split it into separate drives." }
        if !isReview, draft.endDate > Date().addingTimeInterval(5 * 60) { return "The drive can't end in the future." }
        if let distance = parsedDistance, distance < 0 { return "Distance can't be negative." }
        if let distance = parsedDistance, !distance.isFinite || distance > 5000 { return "That distance is too large. Check the number." }
        if !distanceText.trimmingCharacters(in: .whitespaces).isEmpty, parsedDistance == nil { return "Enter the distance as a number." }
        return nil
    }

    private var overlappingDrive: Drive? {
        store.drives.first { other in
            other.id != draft.id && other.startDate < draft.endDate && draft.startDate < other.endDate
        }
    }

    private var parsedDistance: Double? {
        let t = distanceText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        if let n = f.number(from: t) { return n.doubleValue }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                if isReview { reviewHeader }
                if isReview { forgottenStopSection }
                timeSection
                nightSection
                peopleSection
                distanceSection
                conditionsSection
                notesSection
                if isEdit { deleteSection }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isReview)
            .onChange(of: manualNight) { _, isManual in
                if isManual { manualNightMinutes = (min(autoNightMinutes, draft.totalMinutes) / 5).rounded() * 5 }
            }
            .onAppear {
                guard !didAppear else { return }
                didAppear = true
                if let m = draft.distanceMeters {
                    distanceText = String(format: "%.1f", store.settings.distanceUnit.value(fromMeters: m))
                }
                if case .new = mode {
                    draft.supervisor = store.settings.defaultSupervisor
                    draft.vehicle = store.settings.defaultVehicle
                }
            }
            .alert("Drive Not Saved Yet", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(store.lastSaveError ?? "Your log couldn't be written.") Your drive is still kept safely on this phone. Close and reopen TrackMyDrive, then tap Save again.")
            }
            .confirmationDialog("Discard this drive?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Drive", role: .destructive) {
                    store.discardActiveDrive()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("This drive's time won't be added to your log.")
            }
            .confirmationDialog("Delete this drive?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Drive", role: .destructive) {
                    store.delete([draft.id])
                    dismiss()
                }
            } message: {
                Text("You can restore it from Settings ▸ Recently Deleted for \(DriveStore.trashRetentionDays) days.")
            }
            .alert("That's a long drive", isPresented: $showLongDriveWarning) {
                Button("Save Anyway") { commit() }
                Button("Review Times", role: .cancel) {}
            } message: {
                Text("This drive is \(Fmt.duration(minutes: draft.totalMinutes)). If you forgot to stop the timer, adjust the end time before saving.")
            }
        }
    }

    // MARK: Sections

    private var reviewHeader: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                Text(Fmt.duration(minutes: draft.totalMinutes))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                HStack(spacing: 16) {
                    Label(Fmt.duration(minutes: currentNightMinutes), systemImage: "moon.fill").foregroundStyle(Theme.night)
                    if let m = draft.distanceMeters {
                        Label(Fmt.distance(meters: m, unit: store.settings.distanceUnit), systemImage: "road.lanes")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                if draft.route.count > 1 {
                    RouteMap(route: draft.route)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    /// If the phone stopped moving long before Stop was tapped, offer to end the drive at that point.
    @ViewBuilder private var forgottenStopSection: some View {
        if let active = store.activeDrive, let lastFix = active.lastFixDate,
           (active.stoppedAt ?? Date()).timeIntervalSince(lastFix) > 20 * 60,
           lastFix > draft.startDate, abs(draft.endDate.timeIntervalSince(lastFix)) > 60 {
            Section {
                Button {
                    draft.endDate = lastFix
                } label: {
                    Label("End at \(Fmt.time.string(from: lastFix)) instead", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                }
            } footer: {
                Text("The car stopped moving at \(Fmt.time.string(from: lastFix)), \(Fmt.duration(minutes: (active.stoppedAt ?? Date()).timeIntervalSince(lastFix) / 60)) before the drive was stopped. Forgot to tap Stop?")
            }
        }
    }

    private var timeSection: some View {
        Section {
            DatePicker("Start", selection: startBinding, in: ...Date().addingTimeInterval(5 * 60))
            DatePicker("End", selection: $draft.endDate, in: draft.startDate...)
            if case .new = mode {
                HStack(spacing: 8) {
                    Text("Length").foregroundStyle(.secondary)
                    Spacer()
                    ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                        Button(minutes < 60 ? "\(minutes)m" : minutes == 60 ? "1h" : "1.5h") {
                            draft.endDate = draft.startDate.addingTimeInterval(Double(minutes) * 60)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(abs(draft.totalMinutes - Double(minutes)) < 0.5 ? Color.accentColor : Color.secondary)
                    }
                }
            }
        } header: {
            Text("When")
        } footer: {
            if let error = validationError {
                Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
            } else if let other = overlappingDrive {
                Label("Overlaps your drive on \(Fmt.dateTime.string(from: other.startDate)). Check this isn't a duplicate.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Total: \(Fmt.duration(minutes: draft.totalMinutes))")
            }
        }
    }

    /// Moving the start keeps the drive's length the same, which is what people expect when fixing a date.
    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.startDate },
            set: { newStart in
                let length = draft.duration
                draft.startDate = newStart
                draft.endDate = newStart.addingTimeInterval(length)
            }
        )
    }

    private var currentNightMinutes: Double {
        manualNight ? min(manualNightMinutes, draft.totalMinutes) : min(autoNightMinutes, draft.totalMinutes)
    }

    private var nightSection: some View {
        Section {
            HStack {
                Label("Night time", systemImage: "moon.stars.fill")
                    .foregroundStyle(Theme.night)
                Spacer()
                Text(Fmt.duration(minutes: currentNightMinutes))
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            Toggle("Enter night time myself", isOn: $manualNight.animation())
            if manualNight {
                Stepper(value: $manualNightMinutes, in: 0...max(0, draft.totalMinutes.rounded()), step: 5) {
                    Text("\(Fmt.duration(minutes: min(manualNightMinutes, draft.totalMinutes))) at night")
                }
            }
        } header: {
            Text("Night Driving")
        } footer: {
            Text(nightFooter)
        }
    }

    private var nightFooter: String {
        if manualNight { return "Night time is set by hand and won't be recalculated." }
        let s = store.settings
        let lat = draft.startLatitude ?? s.lastKnownLatitude
        let lon = draft.startLongitude ?? s.lastKnownLongitude
        if s.nightMode == .sunsetToSunrise, let lat, let lon,
           let sunset = SolarCalculator.sunEvent(.sunset, on: draft.startDate, latitude: lat, longitude: lon) {
            let offset = s.nightOffsetMinutes > 0 ? " + \(s.nightOffsetMinutes) min" : ""
            return "Counted automatically from sunset (\(Fmt.time.string(from: sunset))\(offset)) to sunrise."
        }
        if s.nightMode == .sunsetToSunrise {
            return "Location unknown, so night uses your fixed hours (\(Fmt.timeOfDay(minutes: s.fixedNightStartMinutes))–\(Fmt.timeOfDay(minutes: s.fixedNightEndMinutes)))."
        }
        return "Counted automatically between \(Fmt.timeOfDay(minutes: s.fixedNightStartMinutes)) and \(Fmt.timeOfDay(minutes: s.fixedNightEndMinutes))."
    }

    private var peopleSection: some View {
        Section("Supervisor & Vehicle") {
            NameField(placeholder: "Supervisor name", text: $draft.supervisor, options: store.settings.supervisorOptions)
            NameField(placeholder: "Vehicle (optional)", text: $draft.vehicle, options: store.settings.vehicleOptions)
        }
    }

    private var distanceSection: some View {
        Section {
            HStack {
                TextField("Distance", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .distance)
                Text(store.settings.distanceUnit.abbreviation).foregroundStyle(.secondary)
            }
        } header: {
            Text("Distance")
        } footer: {
            if draft.source == .tracked, draft.distanceMeters != nil {
                Text("Measured by GPS. You can correct it if needed.")
            }
        }
    }

    private var conditionsSection: some View {
        Group {
            Section("Weather") {
                ChipPicker(options: WeatherCondition.allCases, selection: $draft.weather, label: \.label, symbol: \.symbol)
                    .padding(.vertical, 4)
            }
            Section("Roads") {
                ChipPicker(options: RoadType.allCases, selection: $draft.roads, label: \.label, symbol: \.symbol)
                    .padding(.vertical, 4)
            }
            Section("Skills Practiced") {
                ChipPicker(options: DrivingSkill.allCases, selection: $draft.skills, label: \.label, symbol: \.symbol)
                    .padding(.vertical, 4)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("What went well? What to work on?", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
                .focused($focusedField, equals: .notes)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Drive", role: .destructive) { confirmDelete = true }
                .frame(maxWidth: .infinity)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if isReview {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Resume Drive", systemImage: "play.fill") { store.resumeDrive() }
                    Button("Discard Drive", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isReview ? "Save" : "Done", action: attemptSave)
                .fontWeight(.semibold)
                .disabled(validationError != nil)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
        }
    }

    // MARK: Saving

    private func attemptSave() {
        guard validationError == nil else { return }
        if draft.duration > 6 * 3600 {
            showLongDriveWarning = true
        } else {
            commit()
        }
    }

    private func commit() {
        guard validationError == nil else { return }
        var d = draft
        d.supervisor = d.supervisor.trimmingCharacters(in: .whitespacesAndNewlines)
        d.vehicle = d.vehicle.trimmingCharacters(in: .whitespacesAndNewlines)
        d.notes = d.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        d.nightMinutesIsManual = manualNight
        d.nightMinutes = currentNightMinutes
        if let value = parsedDistance {
            // Keep the exact GPS figure if the user didn't change the displayed value.
            let shown = d.distanceMeters.map { String(format: "%.1f", store.settings.distanceUnit.value(fromMeters: $0)) }
            if shown != distanceText.trimmingCharacters(in: .whitespaces) {
                d.distanceMeters = store.settings.distanceUnit.meters(from: value)
            }
        } else {
            d.distanceMeters = nil
        }
        Haptics.success()
        switch mode {
        case .new:
            store.add(d)
            dismiss()
        case .edit:
            store.update(d)
            dismiss()
        case .review:
            if !store.finishActiveDrive(with: d) { saveFailed = true }
        }
    }

    private static func roundedToFiveMinutes(_ date: Date) -> Date {
        let interval = 5.0 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / interval).rounded(.down) * interval)
    }
}

/// Read-only map with the drive's route.
struct RouteMap: View {
    let route: [RoutePoint]

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = coordinates.first {
                Annotation("Start", coordinate: first) {
                    Circle().fill(.green).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let last = coordinates.last, coordinates.count > 1 {
                Annotation("End", coordinate: last) {
                    Circle().fill(.red).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}
