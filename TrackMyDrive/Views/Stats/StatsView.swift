import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: DriveStore
    @State private var weeks = 8

    var body: some View {
        let stats = store.stats
        let unit = store.settings.distanceUnit
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(title: "Total", value: Fmt.duration(minutes: stats.totalMinutes),
                                 detail: "\(Int((stats.totalProgress * 100).rounded()))% of goal", symbol: "clock.fill")
                        StatTile(title: "Night", value: Fmt.duration(minutes: stats.nightMinutes),
                                 detail: "\(Int((stats.nightProgress * 100).rounded()))% of goal", symbol: "moon.fill", tint: Theme.night)
                        StatTile(title: "Day", value: Fmt.duration(minutes: stats.dayMinutes),
                                 detail: stats.totalMinutes > 0 ? "\(Int((stats.dayMinutes / stats.totalMinutes * 100).rounded()))% of your time" : nil,
                                 symbol: "sun.max.fill", tint: Theme.day)
                        StatTile(title: "Drives", value: "\(stats.driveCount)",
                                 detail: "avg \(Fmt.duration(minutes: stats.averageMinutes))", symbol: "car.fill", tint: .secondary)
                        StatTile(title: "Distance", value: Fmt.distance(meters: stats.distanceMeters, unit: unit, decimals: 0),
                                 detail: stats.driveCount > 0 ? "avg \(Fmt.distance(meters: stats.distanceMeters / Double(stats.driveCount), unit: unit))" : nil,
                                 symbol: "road.lanes", tint: .secondary)
                        StatTile(title: "Streak", value: "\(stats.currentStreak()) day\(stats.currentStreak() == 1 ? "" : "s")",
                                 detail: "last 7 days: \(Fmt.duration(minutes: stats.minutes(inLast: 7)))", symbol: "flame.fill", tint: .secondary)
                        StatTile(title: "Bad Weather", value: Fmt.duration(minutes: stats.adverseWeatherMinutes),
                                 detail: stats.totalMinutes > 0 ? "\(Int((stats.adverseWeatherMinutes / stats.totalMinutes * 100).rounded()))% of your time" : nil,
                                 symbol: "cloud.rain.fill", tint: .secondary)
                        StatTile(title: "Longest", value: stats.longestDrive.map { Fmt.duration(minutes: $0.totalMinutes) } ?? "—",
                                 detail: stats.longestDrive.map { Fmt.mediumDate.string(from: $0.startDate) }, symbol: "trophy.fill", tint: .secondary)
                    }

                    if let date = stats.projectedCompletion() {
                        Banner(symbol: "calendar.badge.clock", title: "On pace to finish \(Fmt.mediumDate.string(from: date))",
                               message: "Based on your driving over the last 30 days.", tint: .accentColor)
                    } else if stats.goalsComplete, stats.driveCount > 0 {
                        Banner(symbol: "checkmark.seal.fill", title: "Requirements met",
                               message: "You've logged enough total and night hours. Export your PDF log from Settings ▸ Backup & Export.",
                               tint: Theme.good)
                    }

                    weeklyChart(stats)
                    breakdown(title: "Weather", rows: stats.minutesByWeather(), total: stats.totalMinutes)
                    breakdown(title: "Road Types", rows: stats.minutesByRoad(), total: stats.totalMinutes)
                    skills(stats)
                    supervisors(stats)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Stats")
        }
    }

    private func weeklyChart(_ stats: LogStats) -> some View {
        let buckets = stats.weeklyBuckets(count: weeks)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Hours per Week").font(.headline)
                    Spacer()
                    Picker("Range", selection: $weeks) {
                        Text("8 wk").tag(8)
                        Text("26 wk").tag(26)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                Chart {
                    ForEach(buckets) { b in
                        BarMark(x: .value("Week", b.weekStart, unit: .weekOfYear), y: .value("Hours", b.dayMinutes / 60))
                            .foregroundStyle(by: .value("Type", "Day"))
                        BarMark(x: .value("Week", b.weekStart, unit: .weekOfYear), y: .value("Hours", b.nightMinutes / 60))
                            .foregroundStyle(by: .value("Type", "Night"))
                    }
                }
                .chartForegroundStyleScale(["Day": Theme.day, "Night": Theme.night])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: weeks > 8 ? 4 : 1)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartYAxisLabel("hours")
                .frame(height: 200)
                if buckets.allSatisfy({ $0.dayMinutes + $0.nightMinutes == 0 }) {
                    Text("No drives in this period yet.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func breakdown(title: String, rows: [LogStats.CategoryTotal], total: Double) -> some View {
        if !rows.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.headline)
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(row.label, systemImage: row.symbol).font(.subheadline)
                                Spacer()
                                Text(Fmt.duration(minutes: row.minutes)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                Capsule().fill(Color(.tertiarySystemFill))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color.accentColor.gradient)
                                            .frame(width: max(6, geo.size.width * (total > 0 ? min(1, row.minutes / total) : 0)))
                                    }
                            }
                            .frame(height: 6)
                        }
                    }
                    Text("A drive can count toward more than one category.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func skills(_ stats: LogStats) -> some View {
        let counts = stats.skillCounts()
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Skills Practiced").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(counts) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.count > 0 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.count > 0 ? Theme.good : Color.secondary)
                            Text(item.skill.label).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if item.count > 0 {
                                Text("×\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func supervisors(_ stats: LogStats) -> some View {
        let rows = stats.minutesBySupervisor()
        if !rows.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Supervisors").font(.headline)
                    ForEach(rows) { row in
                        HStack {
                            Label(row.label, systemImage: row.symbol).font(.subheadline)
                            Spacer()
                            Text(Fmt.duration(minutes: row.minutes)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
