import Foundation

/// Builds dated export files in a temporary folder for the share sheet.
@MainActor
enum ExportService {
    enum Kind { case pdf, csv, json }

    private static var directory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func baseName(_ store: DriveStore) -> String {
        let name = store.settings.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let prefix = safe.isEmpty ? "TrackMyDrive" : "\(safe) TrackMyDrive"
        return "\(prefix) Log \(Fmt.fileStamp.string(from: Date()))"
    }

    static func makeFile(_ kind: Kind, store: DriveStore) throws -> URL {
        let data: Data
        let ext: String
        switch kind {
        case .pdf:
            guard let pdf = PDFLogRenderer.render(drives: store.drives, settings: store.settings, stats: store.stats) else {
                throw CocoaError(.fileWriteUnknown)
            }
            data = pdf
            ext = "pdf"
        case .csv:
            data = Data(TextLogFormatter.csv(drives: store.drives, settings: store.settings).utf8)
            ext = "csv"
        case .json:
            data = try BackupCodec.encode(store.archive, pretty: true)
            ext = "json"
        }
        let url = directory.appendingPathComponent("\(baseName(store)).\(ext)")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func notesText(store: DriveStore) -> String {
        TextLogFormatter.notesBackup(drives: store.drives, settings: store.settings, archive: store.archive)
    }
}
