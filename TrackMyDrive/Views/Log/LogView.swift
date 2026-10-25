import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: DriveStore
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var showingNewDrive = false
    @State private var editingDrive: Drive?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All Drives", night = "Night", day = "Day", tracked = "Tracked", manual = "Entered by Hand", adverse = "Bad Weather"
        var id: String { rawValue }
    }

    private var filtered: [Drive] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.drives.filter { d in
            switch filter {
            case .all: break
            case .night: if d.clampedNightMinutes <= 0 { return false }
            case .day: if d.clampedNightMinutes > 0 { return false }
            case .tracked: if d.source != .tracked { return false }
            case .manual: if d.source != .manual { return false }
            case .adverse: if !d.weather.contains(where: \.isAdverse) { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = [d.supervisor, d.vehicle, d.notes, d.startPlaceName ?? "", d.endPlaceName ?? "",
                            Fmt.conditions(d), Fmt.fullDate.string(from: d.startDate)].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private struct MonthGroup: Identifiable {
        let month: Date
        let drives: [Drive]
        var id: Date { month }
        var totalMinutes: Double { drives.reduce(0) { $0 + $1.totalMinutes } }
    }

    private var groups: [MonthGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { d in
            cal.date(from: cal.dateComponents([.year, .month], from: d.startDate)) ?? d.startDate
        }
        return grouped.map { MonthGroup(month: $0.key, drives: $0.value.sorted { $0.startDate > $1.startDate }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.drives.isEmpty {
                    ContentUnavailableView {
                        Label("No Drives Yet", systemImage: "car.side")
                    } description: {
                        Text("Drives you time or enter by hand will appear here.")
                    } actions: {
                        Button("Log a Past Drive") { showingNewDrive = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    list
                }
            }
            .navigationTitle("Driving Log")
            .searchable(text: $searchText, prompt: "Supervisor, place, notes…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewDrive = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Log a drive")
                }
            }
            .sheet(isPresented: $showingNewDrive) { DriveEditorView(mode: .new) }
            .sheet(item: $editingDrive) { DriveEditorView(mode: .edit($0)) }
        }
    }

    private var list: some View {
        List {
            if filter != .all {
                Section {
                    let stats = LogStats(drives: filtered, settings: store.settings)
                    HStack {
                        Text("\(filtered.count) drive\(filtered.count == 1 ? "" : "s")")
                        Spacer()
                        Text(Fmt.duration(minutes: stats.totalMinutes)).font(.body.weight(.semibold).monospacedDigit())
                    }
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.drives) { drive in
                        NavigationLink {
                            DriveDetailView(driveID: drive.id)
                        } label: {
                            DriveRow(drive: drive, unit: store.settings.distanceUnit)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation { store.delete([drive.id]) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { editingDrive = drive } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingDrive = drive }
                            Button("Delete", systemImage: "trash", role: .destructive) { store.delete([drive.id]) }
                        }
                    }
                } header: {
                    HStack {
                        Text(Fmt.monthYear.string(from: group.month))
                        Spacer()
                        Text(Fmt.duration(minutes: group.totalMinutes)).monospacedDigit()
                    }
                }
            }
            Section {
            } footer: {
                Text("Deleted drives stay in Settings ▸ Recently Deleted for \(DriveStore.trashRetentionDays) days.")
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct DriveRow: View {
    let drive: Drive
    let unit: DistanceUnit

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill((drive.isMostlyNight ? Theme.night : Theme.day).opacity(0.16))
                Image(systemName: drive.isMostlyNight ? "moon.fill" : "sun.max.fill")
                    .foregroundStyle(drive.isMostlyNight ? Theme.night : Theme.day)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.dayMonth.string(from: drive.startDate))
                    .font(.subheadline.weight(.semibold))
                Text("\(Fmt.time.string(from: drive.startDate)) – \(Fmt.time.string(from: drive.endDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !drive.supervisor.isEmpty || drive.distanceMeters != nil {
                    HStack(spacing: 6) {
                        if !drive.supervisor.isEmpty {
                            Label(drive.supervisor, systemImage: "person.fill").lineLimit(1)
                        }
                        if let m = drive.distanceMeters {
                            Label(Fmt.distance(meters: m, unit: unit), systemImage: "road.lanes").lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .labelStyle(CompactLabelStyle())
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.duration(minutes: drive.totalMinutes))
                    .font(.headline.monospacedDigit())
                if drive.clampedNightMinutes > 0 {
                    Label(Fmt.duration(minutes: drive.clampedNightMinutes), systemImage: "moon.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.night)
                        .labelStyle(CompactLabelStyle())
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
