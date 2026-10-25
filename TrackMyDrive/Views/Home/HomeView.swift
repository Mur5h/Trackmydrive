import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: DriveStore
    @Binding var selectedTab: RootView.Tab
    var openActiveDrive: () -> Void

    @State private var showingManualEntry = false
    @State private var sharePayload: SharePayload?
    @State private var exportError: String?

    var body: some View {
        let stats = store.stats
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    banners
                    progressCard(stats)
                    driveButton
                    quickActions
                    backupCard
                    recentDrives
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle(greeting)
            .sheet(isPresented: $showingManualEntry) {
                DriveEditorView(mode: .new)
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items) { type, completed in
                    guard completed else { return }
                    store.markExternalBackup(toNotes: type == ShareSheet.notesActivity)
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Couldn't create backup", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var greeting: String {
        let first = store.settings.studentName.split(separator: " ").first.map(String.init) ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return first.isEmpty ? part : "\(part), \(first)"
    }

    // MARK: Sections

    @ViewBuilder private var banners: some View {
        if let warning = store.loadWarning {
            Banner(symbol: "exclamationmark.triangle.fill", title: "Log recovered", message: warning, tint: .orange,
                   dismiss: { store.loadWarning = nil })
        }
        if let error = store.lastSaveError {
            Banner(symbol: "xmark.octagon.fill", title: "Not saved", message: error, tint: .red)
        }
    }

    private func progressCard(_ stats: LogStats) -> some View {
        Card(padding: 20) {
            VStack(spacing: 18) {
                HStack(spacing: 22) {
                    ZStack {
                        ProgressRing(progress: stats.totalProgress, color: .accentColor, lineWidth: 18)
                            .frame(width: 150, height: 150)
                        ProgressRing(progress: stats.nightProgress, color: Theme.night, lineWidth: 14)
                            .frame(width: 106, height: 106)
                        VStack(spacing: 0) {
                            Text(Fmt.hoursShort(minutes: stats.totalMinutes))
                                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                                .contentTransition(.numericText())
                            Text("of \(Fmt.hoursShort(minutes: store.settings.totalGoalMinutes)) hrs")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Fmt.duration(minutes: stats.totalMinutes)) of \(Fmt.hoursShort(minutes: store.settings.totalGoalMinutes)) hours. Night \(Fmt.duration(minutes: stats.nightMinutes)) of \(Fmt.hoursShort(minutes: store.settings.nightGoalMinutes)) hours.")

                    VStack(alignment: .leading, spacing: 14) {
                        legendRow(color: .accentColor, title: "Total", value: stats.totalMinutes, goal: store.settings.totalGoalMinutes)
                        legendRow(color: Theme.night, title: "Night", value: stats.nightMinutes, goal: store.settings.nightGoalMinutes)
                        HStack(spacing: 6) {
                            Circle().fill(Theme.day).frame(width: 8, height: 8)
                            Text("Day \(Fmt.duration(minutes: stats.dayMinutes))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Divider()

                HStack {
                    if stats.goalsComplete {
                        Label("All requirements met!", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.good)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Fmt.duration(minutes: stats.totalRemainingMinutes)) to go")
                                .font(.subheadline.weight(.semibold))
                            if stats.nightRemainingMinutes > 0 {
                                Text("incl. \(Fmt.duration(minutes: stats.nightRemainingMinutes)) at night")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let date = stats.projectedCompletion() {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("On pace for").font(.caption).foregroundStyle(.secondary)
                                Text(Fmt.mediumDate.string(from: date)).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func legendRow(color: Color, title: String, value: Double, goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text("\(Fmt.duration(minutes: value))")
                .font(.headline.monospacedDigit())
            Text("goal \(Fmt.hoursShort(minutes: goal))h")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var driveButton: some View {
        if let active = store.activeDrive {
            Button(action: openActiveDrive) {
                HStack(spacing: 14) {
                    Image(systemName: active.stoppedAt == nil ? "car.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.stoppedAt == nil ? "Drive in progress" : "Drive ready to save")
                            .font(.headline)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Fmt.clock(seconds: active.elapsed(at: context.date)))
                                .font(.subheadline.monospacedDigit())
                                .opacity(0.9)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.headline)
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(active.stoppedAt == nil ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.good.gradient),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Haptics.success()
                store.startDrive(supervisor: store.settings.defaultSupervisor, vehicle: store.settings.defaultVehicle)
                openActiveDrive()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "steeringwheel")
                        .font(.title)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Drive").font(.title3.weight(.bold))
                        Text(store.settings.defaultSupervisor.isEmpty ? "Times your drive and tracks distance"
                             : "Supervised by \(store.settings.defaultSupervisor)")
                            .font(.subheadline).opacity(0.85)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "play.fill").font(.title3)
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts timing a supervised drive")
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction(title: "Log Past Drive", symbol: "square.and.pencil", tint: .accentColor) {
                showingManualEntry = true
            }
            quickAction(title: "Back Up to Notes", symbol: "note.text.badge.plus", tint: .orange) {
                backUpToNotes()
            }
        }
    }

    private func quickAction(title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var backupCard: some View {
        let changes = store.changesSinceExternalBackup
        let last = store.settings.lastExternalBackup
        let stale = changes > 0 && (last == nil || changes >= 3 || Date().timeIntervalSince(last!) > 7 * 86_400)
        if stale {
            Banner(
                symbol: "exclamationmark.icloud.fill",
                title: "\(changes) drive\(changes == 1 ? "" : "s") not backed up",
                message: last.map { "Last off-phone backup \(Fmt.relative($0)). Save a copy to Notes so a lost or broken phone can't erase your hours." }
                    ?? "Save a copy to Notes so a lost or broken phone can't erase your hours.",
                tint: .orange,
                actionTitle: "Back Up Now",
                action: backUpToNotes
            )
        } else if let last {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.icloud.fill").foregroundStyle(Theme.good)
                Text("Backed up \(Fmt.relative(last))").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder private var recentDrives: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Recent Drives", trailing: store.drives.isEmpty ? nil : AnyView(
                Button("See All") { selectedTab = .log }.font(.subheadline.weight(.semibold))
            ))
            if store.drives.isEmpty {
                Card {
                    VStack(spacing: 8) {
                        Image(systemName: "road.lanes").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No drives yet").font(.headline)
                        Text("Tap Start Drive when you head out, or log a past drive by hand.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.drives.prefix(4).enumerated()), id: \.element.id) { index, drive in
                        NavigationLink {
                            DriveDetailView(driveID: drive.id)
                        } label: {
                            DriveRow(drive: drive, unit: store.settings.distanceUnit)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if index < min(4, store.drives.count) - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func backUpToNotes() {
        do {
            let pdf = try ExportService.makeFile(.pdf, store: store)
            sharePayload = SharePayload(items: [ExportService.notesText(store: store), pdf], isNotesBackup: true)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
