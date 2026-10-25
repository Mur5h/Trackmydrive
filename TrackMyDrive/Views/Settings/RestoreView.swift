import SwiftUI
import UniformTypeIdentifiers

struct RestoreView: View {
    @EnvironmentObject private var store: DriveStore
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText = ""
    @State private var showingImporter = false
    @State private var pending: LogArchive?
    @State private var restoreSettings = true
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    var body: some View {
        Form {
            Section {
                Button {
                    if let text = UIPasteboard.general.string {
                        pastedText = text
                        parse(text)
                    } else {
                        errorMessage = "The clipboard is empty. In Notes, open your TrackMyDrive backup, tap ••• ▸ Select All… or select the text, then Copy."
                    }
                } label: {
                    Label("Paste From Clipboard", systemImage: "doc.on.clipboard")
                }
                TextEditor(text: $pastedText)
                    .frame(minHeight: 120)
                    .font(.footnote.monospaced())
                    .overlay(alignment: .topLeading) {
                        if pastedText.isEmpty {
                            Text("…or paste the whole backup note here")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                if !pastedText.isEmpty && pending == nil {
                    Button("Read Backup") { parse(pastedText) }
                }
            } header: {
                Text("From Notes")
            } footer: {
                Text("Open your backup note, copy all of it (including the BEGIN and END lines), then tap Paste.")
            }

            Section {
                Button {
                    showingImporter = true
                } label: {
                    Label("Choose Backup File…", systemImage: "folder")
                }
            } header: {
                Text("From a File")
            } footer: {
                Text("Pick a .json backup from Files or iCloud Drive — including the automatic daily backups in On My iPhone ▸ TrackMyDrive ▸ Backups.")
            }

            if let archive = pending {
                previewSection(archive)
            }
        }
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .plainText, .text]) { result in
            switch result {
            case .success(let url):
                readFile(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't Read Backup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Restore Complete", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("Done") { dismiss() }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func previewSection(_ archive: LogArchive) -> some View {
        let stats = LogStats(drives: archive.drives, settings: archive.settings)
        let newCount = archive.drives.filter { d in !store.drives.contains { $0.id == d.id } }.count
        return Section {
            LabeledContent("Backup from", value: Fmt.dateTime.string(from: archive.exportedAt))
            if !archive.settings.studentName.isEmpty {
                LabeledContent("Driver", value: archive.settings.studentName)
            }
            LabeledContent("Drives", value: "\(archive.drives.count)")
            LabeledContent("Total time", value: Fmt.duration(minutes: stats.totalMinutes))
            LabeledContent("Night time", value: Fmt.duration(minutes: stats.nightMinutes))
            LabeledContent("New to this phone", value: "\(newCount)")
            Toggle("Also restore settings & goals", isOn: $restoreSettings)
            Button {
                let summary = store.importArchive(archive, restoreSettings: restoreSettings)
                Haptics.success()
                pending = nil
                pastedText = ""
                resultMessage = summary.description
            } label: {
                Text("Restore \(archive.drives.count) Drive\(archive.drives.count == 1 ? "" : "s")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
        } header: {
            Text("Backup Found")
        } footer: {
            Text("Drives already in your log are kept. If the backup has a newer edit of a drive, the newer version is used.")
        }
    }

    private func parse(_ text: String) {
        do {
            pending = try BackupCodec.decode(text: text)
        } catch {
            pending = nil
            errorMessage = error.localizedDescription
        }
    }

    private func readFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                pending = try BackupCodec.decode(text: text)
            } else {
                pending = try BackupCodec.decode(data)
            }
        } catch {
            pending = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct RecentlyDeletedView: View {
    @EnvironmentObject private var store: DriveStore
    @State private var confirmEmpty = false

    var body: some View {
        Group {
            if store.recentlyDeleted.isEmpty {
                ContentUnavailableView("No Recently Deleted Drives", systemImage: "trash",
                                       description: Text("Deleted drives are kept here for \(DriveStore.trashRetentionDays) days."))
            } else {
                List {
                    Section {
                        ForEach(store.recentlyDeleted) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                DriveRow(drive: item.drive, unit: store.settings.distanceUnit)
                                Text("Deleted \(Fmt.relative(item.deletedAt)) · \(daysLeft(item)) left")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button { withAnimation { store.restoreDeleted(item) } } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.permanentlyDelete(item) } label: {
                                    Label("Delete Forever", systemImage: "trash.slash")
                                }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") { store.restoreDeleted(item) }
                                Button("Delete Forever", systemImage: "trash.slash", role: .destructive) { store.permanentlyDelete(item) }
                            }
                        }
                    } footer: {
                        Text("Swipe right to restore a drive.")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Restore All") {
                            for item in store.recentlyDeleted { store.restoreDeleted(item) }
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete All Forever", role: .destructive) { confirmEmpty = true }
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Permanently delete these drives?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) { store.emptyRecentlyDeleted() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func daysLeft(_ item: DeletedDrive) -> String {
        let expires = Calendar.current.date(byAdding: .day, value: DriveStore.trashRetentionDays, to: item.deletedAt) ?? item.deletedAt
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0)
        return days == 1 ? "1 day" : "\(days) days"
    }
}
