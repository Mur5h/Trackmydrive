import Foundation

/// Keeps a copy of the log in a folder the user picked (normally in iCloud Drive), refreshed after
/// every change. Works without the iCloud entitlement: the folder is reached through a security-scoped
/// bookmark, and iCloud Drive syncs whatever lands in it.
struct CloudFolderState: Codable, Equatable {
    var bookmark: Data
    var folderName: String
    /// True when the folder lives in iCloud Drive (so a copy really leaves the phone).
    var isInICloud: Bool
    var lastBackup: Date?
    var lastError: String?
}

enum CloudFolderBackup {
    static let backupFileName = "TrackMyDrive Backup.json"
    static let pdfFileName = "TrackMyDrive Driving Log.pdf"
    static let textFileName = "TrackMyDrive Driving Log.txt"
    static let historyFolderName = "History"
    static let historyToKeep = 60

    private static var stateURL: URL { StorePaths.appSupport.appendingPathComponent("cloud-folder.json") }

    static func loadState() -> CloudFolderState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? BackupCodec.makeDecoder().decode(CloudFolderState.self, from: data)
    }

    static func saveState(_ state: CloudFolderState?) {
        guard let state else {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        if let data = try? BackupCodec.makeEncoder(pretty: false).encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    /// Makes a bookmark for a folder chosen in the Files picker.
    static func makeState(for url: URL) throws -> CloudFolderState {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let ubiquitous = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
        let inICloud = ubiquitous || url.path.contains("/Mobile Documents/")
        return CloudFolderState(bookmark: bookmark, folderName: url.lastPathComponent, isInICloud: inICloud)
    }

    struct Payload: Sendable {
        let archiveJSON: Data
        let pdf: Data?
        let text: Data?
    }

    /// Writes the backup files into the folder. Runs off the main thread; returns the refreshed bookmark
    /// if iOS reported the old one as stale.
    static func write(_ payload: Payload, bookmark: Data) async throws -> Data? {
        try await Task.detached(priority: .utility) {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard folder.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileWriteNoPermission)
            }
            defer { folder.stopAccessingSecurityScopedResource() }

            try coordinatedWrite(payload.archiveJSON, to: folder.appendingPathComponent(backupFileName))
            if let pdf = payload.pdf { try coordinatedWrite(pdf, to: folder.appendingPathComponent(pdfFileName)) }
            if let text = payload.text { try coordinatedWrite(text, to: folder.appendingPathComponent(textFileName)) }

            // One dated copy per day, so a bad edit can be undone from an older day.
            let history = folder.appendingPathComponent(historyFolderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            try? coordinatedWrite(payload.archiveJSON, to: history.appendingPathComponent("TrackMyDrive-\(f.string(from: Date())).json"))
            pruneHistory(in: history)

            return stale ? try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
        }.value
    }

    private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    private static func pruneHistory(in dir: URL) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in files.dropFirst(historyToKeep) { try? fm.removeItem(at: url) }
    }
}
