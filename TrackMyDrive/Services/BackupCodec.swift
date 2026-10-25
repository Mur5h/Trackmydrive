import Foundation

/// Everything needed to rebuild the log on a new phone.
struct LogArchive: Codable {
    var formatVersion: Int = 1
    var exportedAt: Date = Date()
    var settings: AppSettings
    var drives: [Drive]
    var recentlyDeleted: [DeletedDrive] = []
    /// Drive entries that couldn't be read while decoding. Not saved.
    var skippedDrives = 0

    enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, settings, drives, recentlyDeleted
    }

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
        // Decode drives one by one so a single damaged entry doesn't hide all the others.
        drives = []
        if c.contains(.drives), try !c.decodeNil(forKey: .drives) {
            var list = try c.nestedUnkeyedContainer(forKey: .drives)
            while !list.isAtEnd {
                if let d = try? list.decode(Drive.self) {
                    drives.append(d)
                } else {
                    guard (try? list.decode(SkippedValue.self)) != nil else { break }
                    skippedDrives += 1
                }
            }
        }
        recentlyDeleted = (try? c.decodeIfPresent([DeletedDrive].self, forKey: .recentlyDeleted)) ?? []
    }
}

/// Consumes one array element of any shape.
private struct SkippedValue: Decodable {
    init(from decoder: Decoder) throws {}
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
        // One bad number (e.g. an infinite distance) must never stop the whole log from saving.
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }

    static func encode(_ archive: LogArchive, pretty: Bool = false) throws -> Data {
        try makeEncoder(pretty: pretty).encode(archive)
    }

    /// Strict: any damaged drive fails the whole file. Used for the app's own log so a bad file
    /// falls back to the previous copy instead of being saved over with drives missing.
    static func decode(_ data: Data) throws -> LogArchive {
        let archive = try decodeForRestore(data)
        guard archive.skippedDrives == 0 else {
            throw BackupCodecError.unreadable("\(archive.skippedDrives) damaged drive(s)")
        }
        return archive
    }

    /// Lenient: damaged drives are skipped and counted in `skippedDrives`.
    static func decodeForRestore(_ data: Data) throws -> LogArchive {
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

    /// Accepts a pasted note (with the BEGIN/END block), raw base64, or raw JSON. If the BEGIN/END
    /// lines were lost or changed, the longest block of base64 lines in the text is tried instead.
    static func decode(text: String) throws -> LogArchive {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", let data = trimmed.data(using: .utf8) {
            return try decodeForRestore(data)
        }
        let payload: String
        if let begin = trimmed.range(of: beginMarker) {
            let end = trimmed.range(of: endMarker, range: begin.upperBound..<trimmed.endIndex)
            payload = String(trimmed[begin.upperBound..<(end?.lowerBound ?? trimmed.endIndex)])
        } else if trimmed.contains(" ") {
            guard let run = longestBase64Run(in: trimmed) else { throw BackupCodecError.noBackupFound }
            payload = run
        } else {
            payload = trimmed
        }
        let cleaned = payload.filter(isBase64Character)
        guard !cleaned.isEmpty, let data = Data(base64Encoded: cleaned) else {
            throw BackupCodecError.noBackupFound
        }
        return try decodeForRestore(data)
    }

    private static func isBase64Character(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "+" || c == "/" || c == "=")
    }

    /// The longest run of consecutive lines made only of base64 characters (at least 100 of them).
    private static func longestBase64Run(in text: String) -> String? {
        var best = ""
        var current = ""
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if !l.isEmpty, l.allSatisfy(isBase64Character) {
                current += l
            } else {
                if current.count > best.count { best = current }
                current = ""
            }
        }
        if current.count > best.count { best = current }
        return best.count >= 100 ? best : nil
    }
}
