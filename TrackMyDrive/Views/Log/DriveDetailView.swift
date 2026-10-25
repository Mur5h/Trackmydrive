import SwiftUI

struct DriveDetailView: View {
    @EnvironmentObject private var store: DriveStore
    @Environment(\.dismiss) private var dismiss
    let driveID: UUID

    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let drive = store.drive(withID: driveID) {
                content(drive)
            } else {
                ContentUnavailableView("Drive Deleted", systemImage: "trash",
                                       description: Text("You can restore it from Settings ▸ Recently Deleted."))
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ drive: Drive) -> some View {
        let unit = store.settings.distanceUnit
        return ScrollView {
            VStack(spacing: 16) {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.fullDate.string(from: drive.startDate))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(Fmt.time.string(from: drive.startDate)) – \(Fmt.time.string(from: drive.endDate))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(drive.source == .tracked ? "Tracked" : "Entered", systemImage: drive.source == .tracked ? "location.fill" : "pencil")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        Text(Fmt.duration(minutes: drive.totalMinutes))
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        DayNightBar(dayMinutes: drive.dayMinutes, nightMinutes: drive.clampedNightMinutes)
                        HStack {
                            Label("Day \(Fmt.duration(minutes: drive.dayMinutes))", systemImage: "sun.max.fill")
                                .foregroundStyle(Theme.day)
                            Spacer()
                            Label("Night \(Fmt.duration(minutes: drive.clampedNightMinutes))", systemImage: "moon.fill")
                                .foregroundStyle(Theme.night)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }

                if drive.route.count > 1 {
                    RouteMap(route: drive.route)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(title: "Distance", value: Fmt.distance(meters: drive.distanceMeters, unit: unit), symbol: "road.lanes")
                    StatTile(title: "Avg Speed", value: drive.averageSpeedMetersPerSecond.map { Fmt.speed(metersPerSecond: $0, unit: unit) } ?? "—",
                             symbol: "speedometer", tint: .teal)
                    StatTile(title: "Supervisor", value: drive.supervisor.isEmpty ? "—" : drive.supervisor, symbol: "person.fill", tint: .green)
                    StatTile(title: "Vehicle", value: drive.vehicle.isEmpty ? "—" : drive.vehicle, symbol: "car.fill", tint: .orange)
                }

                if let route = drive.routeSummary {
                    Card {
                        Label(route, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }
                }

                if !drive.weather.isEmpty || !drive.roads.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Conditions").font(.headline)
                            FlowLayout(spacing: 8) {
                                ForEach(WeatherCondition.allCases.filter { drive.weather.contains($0) }) { w in
                                    tag(w.label, symbol: w.symbol)
                                }
                                ForEach(RoadType.allCases.filter { drive.roads.contains($0) }) { r in
                                    tag(r.label, symbol: r.symbol)
                                }
                            }
                        }
                    }
                }

                if !drive.skills.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Skills Practiced").font(.headline)
                            FlowLayout(spacing: 8) {
                                ForEach(DrivingSkill.allCases.filter { drive.skills.contains($0) }) { s in
                                    tag(s.label, symbol: s.symbol)
                                }
                            }
                        }
                    }
                }

                if !drive.notes.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes").font(.headline)
                            Text(drive.notes).font(.body)
                        }
                    }
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete Drive", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Text(drive.nightMinutesIsManual ? "Night time entered by hand." : "Night time calculated automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            DriveEditorView(mode: .edit(drive))
        }
        .confirmationDialog("Delete this drive?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Drive", role: .destructive) {
                store.delete([drive.id])
                dismiss()
            }
        } message: {
            Text("You can restore it from Settings ▸ Recently Deleted for \(DriveStore.trashRetentionDays) days.")
        }
    }

    private func tag(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
