import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: DriveStore
    @EnvironmentObject private var location: LocationTracker
    @State private var page = 0
    @State private var name = ""
    @State private var stateCode = ""
    @State private var totalGoal: Double = 50
    @State private var nightGoal: Double = 10
    @State private var supervisor = ""
    @State private var showingRestore = false

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                scrollable(welcome, alignment: .center).tag(0)
                scrollable(profile).tag(1)
                scrollable(requirements).tag(2)
                scrollable(safety).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.3), value: page)
            .padding(.bottom, 18)

            Button(action: next) {
                Text(page == pageCount - 1 ? "Start Logging" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .screenBackground()
        .sheet(isPresented: $showingRestore) {
            NavigationStack {
                RestoreView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showingRestore = false } }
                    }
            }
            .environmentObject(store)
        }
        .onAppear {
            name = store.settings.studentName
            stateCode = store.settings.stateCode
            totalGoal = store.settings.totalGoalHours
            nightGoal = store.settings.nightGoalHours
            supervisor = store.settings.defaultSupervisor
        }
    }

    private func next() {
        if page < pageCount - 1 {
            page += 1
        } else {
            finish()
        }
    }

    private func finish() {
        var s = store.settings
        s.studentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.stateCode = stateCode
        s.totalGoalHours = totalGoal
        s.nightGoalHours = nightGoal
        let sup = supervisor.trimmingCharacters(in: .whitespacesAndNewlines)
        s.defaultSupervisor = sup
        if !sup.isEmpty, !s.supervisors.contains(sup) { s.supervisors.append(sup) }
        s.hasOnboarded = true
        store.settings = s
        location.requestPermission()
        Haptics.success()
    }

    // MARK: Pages

    /// Lets a page scroll on small phones, large text, or with the keyboard up, while still filling the screen.
    private func scrollable<V: View>(_ page: V, alignment: Alignment = .top) -> some View {
        GeometryReader { geo in
            ScrollView {
                page.frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: alignment)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 150, height: 150)
                Image(systemName: "steeringwheel")
                    .font(.system(size: 70, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.accentColor.opacity(0.4), radius: 24, y: 12)
            VStack(spacing: 10) {
                Text("TrackMyDrive")
                    .font(.largeTitle.weight(.bold))
                Text("Log every supervised hour, day and night, and never lose them.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("timer", "One-tap drive timer with GPS distance")
                feature("moon.stars.fill", "Night hours worked out from real sunset times")
                feature("doc.richtext.fill", "DMV-ready PDF log with signature lines")
                feature("note.text.badge.plus", "Backups to Notes, Files and PDF")
            }
            .padding(.top, 8)
            Spacer()
            Button("Restoring from a backup?") { showingRestore = true }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            Text(text).font(.body)
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader("person.crop.circle.fill", "About You", "This appears on your PDF log.")
            VStack(alignment: .leading, spacing: 8) {
                Text("Driver's name").font(.subheadline.weight(.semibold))
                TextField("First and last name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Usual supervisor").font(.subheadline.weight(.semibold))
                TextField("e.g. Mom, Dad, Coach Lee", text: $supervisor)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                Text("You can add more supervisors any time.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader("checklist", "Your Requirements", "Pick your state or set your own goals.")
            Picker("State", selection: $stateCode) {
                Text("Choose a state…").tag("")
                ForEach(StatePreset.all) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.menu)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: stateCode) { _, code in
                if let p = StatePreset.all.first(where: { $0.code == code }) {
                    totalGoal = p.totalHours
                    nightGoal = p.nightHours
                }
            }
            VStack(spacing: 0) {
                Stepper(value: $totalGoal, in: 1...200) {
                    LabeledContent("Total hours", value: "\(Int(totalGoal))")
                }
                .padding(14)
                Divider().padding(.leading, 14)
                Stepper(value: $nightGoal, in: 0...100) {
                    LabeledContent("Night hours", value: "\(Int(nightGoal))")
                }
                .padding(14)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            Text("Presets are common requirements only. Check with your DMV — you can change these later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageHeader("hand.raised.fill", "Safety & Backups", "A few things before your first drive.")
            infoRow("iphone.slash", .red, "Phone down while driving",
                    "Start the drive before you pull out, and let your supervisor handle the app.")
            infoRow("location.fill", .accentColor, "Location for distance & night time",
                    "Used only during a drive to measure distance and find sunset. It never leaves your phone.")
            infoRow("note.text.badge.plus", .orange, "Back up to Notes",
                    "Tap Back Up to Notes after drives. Your hours then live in iCloud too, even if your phone is lost.")
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
    }

    private func pageHeader(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
    }

    private func infoRow(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
