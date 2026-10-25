import SwiftUI

struct BackupView: View {
    @EnvironmentObject private var store: DriveStore
    @State private var sharePayload: SharePayload?
    @State private var errorMessage: String?
    @State private var copiedToClipboard = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: statusSymbol)
                            .font(.largeTitle)
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(statusTitle).font(.headline)
                            Text(statusDetail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button(action: backUpToNotes) {
                        Label("Back Up to Notes", systemImage: "note.text.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Choose **Notes** in the share sheet, then tap **Save**. The note holds a readable copy of every drive, your PDF log, and restore data — and it syncs to iCloud, so it survives a lost or broken phone.")
            }

            Section {
                exportRow("PDF Driving Log", detail: "Printable log with totals and signature lines", symbol: "doc.richtext.fill", tint: .red) {
                    share(.pdf)
                }
                exportRow("Spreadsheet (CSV)", detail: "Opens in Numbers, Excel or Google Sheets", symbol: "tablecells.fill", tint: .green) {
                    share(.csv)
                }
                exportRow("Full Backup File (JSON)", detail: "Save to iCloud Drive or email to yourself", symbol: "archivebox.fill", tint: .indigo) {
                    share(.json)
                }
                exportRow(copiedToClipboard ? "Copied!" : "Copy Backup Text", detail: "Paste into any app — Notes, Messages, email", symbol: "doc.on.doc.fill", tint: .orange) {
                    // Not counted as a backup: nothing has left the phone until it's pasted somewhere.
                    UIPasteboard.general.string = ExportService.notesText(store: store)
                    copiedToClipboard = true
                    Haptics.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToClipboard = false }
                }
            } header: {
                Text("Export")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Saved on this iPhone").font(.subheadline.weight(.semibold))
                        Text("Every change is saved instantly, with a previous copy kept in case of damage. A daily backup, the PDF and a text copy are also kept in the Files app ▸ On My iPhone ▸ TrackMyDrive.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "iphone").foregroundStyle(Color.accentColor)
                }
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Automatic Notes backups with Shortcuts").font(.subheadline.weight(.semibold))
                        Text("In the Shortcuts app, create a Personal Automation (for example, every Sunday). Add TrackMyDrive's **Get Driving Log Backup** action, then Notes' **Create Note** action. Turn off \"Ask Before Running\".")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(.pink)
                }
            } header: {
                Text("How Your Hours Are Protected")
            }

            Section {
                NavigationLink {
                    RestoreView()
                } label: {
                    Label("Restore From Backup", systemImage: "arrow.counterclockwise.icloud")
                }
            } footer: {
                Text("Restoring adds drives from a backup; it never deletes drives already in your log.")
            }
        }
        .navigationTitle("Backup & Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items) { type, completed in
                guard completed, ShareSheet.leavesDevice(type) else { return }
                store.markExternalBackup(toNotes: type == ShareSheet.notesActivity)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Export Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isStale: Bool {
        guard let last = store.settings.lastExternalBackup else { return !store.drives.isEmpty }
        return store.changesSinceExternalBackup > 0 && Date().timeIntervalSince(last) > 86_400
    }

    private var statusSymbol: String { isStale ? "exclamationmark.icloud.fill" : "checkmark.icloud.fill" }
    private var statusColor: Color { isStale ? .orange : Theme.good }

    private var statusTitle: String {
        if store.drives.isEmpty { return "Nothing to back up yet" }
        if store.settings.lastExternalBackup == nil { return "Not backed up yet" }
        let n = store.changesSinceExternalBackup
        return n == 0 ? "Everything is backed up" : "\(n) drive\(n == 1 ? "" : "s") since last backup"
    }

    private var statusDetail: String {
        var parts: [String] = []
        if let last = store.settings.lastExternalBackup { parts.append("Last backup \(Fmt.relative(last))") }
        if let notes = store.settings.lastNotesBackup { parts.append("Notes \(Fmt.relative(notes))") }
        return parts.isEmpty ? "Back up after each drive to be safe." : parts.joined(separator: " · ")
    }

    private func exportRow(_ title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
            }
        }
    }

    private func backUpToNotes() {
        do {
            let pdf = try ExportService.makeFile(.pdf, store: store)
            sharePayload = SharePayload(items: [ExportService.notesText(store: store), pdf], isNotesBackup: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share(_ kind: ExportService.Kind) {
        do {
            sharePayload = SharePayload(items: [try ExportService.makeFile(kind, store: store)])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
