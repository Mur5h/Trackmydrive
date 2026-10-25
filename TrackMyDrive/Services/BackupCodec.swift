import Foundation

/// Everything needed to rebuild the log on a new phone.
struct LogArchive: Codable {
    var formatVersion: Int = 1
    var exportedAt: Date = Date()
    var settings: AppSettings
    var drives: [Drive]
    var recentlyDeleted: [DeletedDrive] = []

    init(settings: AppSettings, drives: [Drive], recentlyDeleted: [DeletedDrive] = []) {
        self.settings = settings
        self.drives = drives
        self.recentlyDeleted = recentlyDeleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? AppSettings()
        drives = try c.decodeIfPresent([Drive].self, forKey: .drives) ?? []
        recentlyDeleted = (try? c.decodeIfPresent([DeletedDrive].self, forKey: .recentlyDeleted)) ?? []
    }
}

enum BackupCodecError: LocalizedError {
    case noBackupFound
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .noBackupFound:
            return "No TrackMyDrive backup was found. Paste the whole note, including the BEGIN and END lines, or choose a .json backup file."
        case .unreadable(let detail):
            return "The backup couldn't be read. It may have been edited or cut off. (\(detail))"
        }
    }
}

enum BackupCodec {
    static let beginMarker = "-----BEGIN TRACKMYDRIVE BACKUP-----"
    static let endMarker = "-----END TRACKMYDRIVE BACKUP-----"

    static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func encode(_ archive: LogArchive, pretty: Bool = false) throws -> Data {
        try makeEncoder(pretty: pretty).encode(archive)
    }

    static func decode(_ data: Data) throws -> LogArchive {
        do {
            return try makeDecoder().decode(LogArchive.self, from: data)
        } catch {
            throw BackupCodecError.unreadable(String(describing: error).prefix(160).description)
        }
    }

    /// A compact copy for the text/Notes backup: routes are dropped to keep the note small.
    static func textBlock(for archive: LogArchive) -> String {
        var slim = archive
        slim.drives = archive.drives.map { var d = $0; d.route = []; return d }
        slim.recentlyDeleted = []
        guard let data = try? encode(slim) else { return "" }
        let b64 = data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        return "\(beginMarker)\n\(b64)\n\(endMarker)"
    }

    /// Accepts a pasted note (with the BEGIN/END block), raw base64, or raw JSON.
    static func decode(text: String) throws -> LogArchive {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", let data = trimmed.data(using: .utf8) {
            return try decode(data)
        }
        var payload = trimmed
        if let begin = trimmed.range(of: beginMarker) {
            guard let end = trimmed.range(of: endMarker, range: begin.upperBound..<trimmed.endIndex) else {
                throw BackupCodecError.unreadable("the END line is missing")
            }
            payload = String(trimmed[begin.upperBound..<end.lowerBound])
        } else if trimmed.contains(" ") {
            throw BackupCodecError.noBackupFound
        }
        let cleaned = payload.filter { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
            .filter { $0.isASCII }
        guard !cleaned.isEmpty, let data = Data(base64Encoded: cleaned) else {
            throw BackupCodecError.noBackupFound
        }
        return try decode(data)
    }
}
