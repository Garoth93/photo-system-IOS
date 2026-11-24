import Foundation

/// User preferences saved in the backup.
public struct SweepSettings: Codable, Equatable, Sendable {
    public var filter: MediaFilter
    public var order: SweepOrder
    public var cloudBackup: Bool

    public init(filter: MediaFilter = .all, order: SweepOrder = .newestFirst, cloudBackup: Bool = true) {
        self.filter = filter
        self.order = order
        self.cloudBackup = cloudBackup
    }

    private enum CodingKeys: String, CodingKey { case filter, order, cloudBackup }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let filter = (try? c.decodeIfPresent(String.self, forKey: .filter)).flatMap { $0 }.flatMap(MediaFilter.init(rawValue:))
        let order = (try? c.decodeIfPresent(String.self, forKey: .order)).flatMap { $0 }.flatMap(SweepOrder.init(rawValue:))
        self.init(
            filter: filter ?? .all,
            order: order ?? .newestFirst,
            cloudBackup: (try? c.decodeIfPresent(Bool.self, forKey: .cloudBackup)).flatMap { $0 } ?? true
        )
    }
}

/// A photo in the backup. `local` is the identifier on this iPhone
/// (`PHAsset.localIdentifier`); `cloud` is the iCloud Photos identifier
/// (`PHCloudIdentifier`), the only one that survives a move to a new iPhone.
/// Never the photo itself.
public struct PhotoRef: Codable, Equatable, Hashable, Sendable {
    public var local: String
    public var cloud: String?

    public init(local: String, cloud: String? = nil) {
        self.local = local
        self.cloud = cloud
    }
}

/// Progress of one album when the backup was made (informative: the
/// progress is recomputed from the photo decisions after a restore).
public struct AlbumSummary: Codable, Equatable, Sendable {
    public var title: String
    public var kind: String
    public var total: Int
    public var reviewed: Int

    public init(title: String, kind: String, total: Int, reviewed: Int) {
        self.title = title
        self.kind = kind
        self.total = total
        self.reviewed = reviewed
    }
}

/// Versioned backup file (JSON): the decisions taken in Sweep, the album
/// progress and the preferences. No photos, thumbnails, tokens or other
/// sensitive data.
public struct BackupFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let appName = "Sweep"

    public var version: Int
    public var app: String
    public var exportedAt: Date
    /// Photos already reviewed and kept.
    public var kept: [PhotoRef]
    /// Photos swiped to the right, not deleted yet (in swipe order).
    public var trash: [PhotoRef]
    public var deletedCount: Int
    public var freedBytes: Int64
    public var albums: [AlbumSummary]
    public var settings: SweepSettings

    /// - Parameter cloudIDs: local identifier → iCloud Photos identifier, when known.
    public init(state: SweepState, settings: SweepSettings, albums: [AlbumSummary] = [],
                cloudIDs: [String: String] = [:], now: Date = Date()) {
        version = Self.currentVersion
        app = Self.appName
        exportedAt = now
        kept = state.kept.sorted().map { PhotoRef(local: $0, cloud: cloudIDs[$0]) }
        trash = state.trash.map { PhotoRef(local: $0, cloud: cloudIDs[$0]) }
        deletedCount = state.deletedCount
        freedBytes = state.freedBytes
        self.albums = albums
        self.settings = settings
    }

    /// Nothing worth saving (an empty app never overwrites a backup).
    public var isEmpty: Bool {
        kept.isEmpty && trash.isEmpty && deletedCount == 0
    }

    /// All the iCloud identifiers in the file.
    public var cloudIDs: [String] {
        (kept + trash).compactMap(\.cloud)
    }

    /// Rebuilds the state for this iPhone.
    /// - Parameters:
    ///   - existing: local identifiers present in the library now.
    ///   - cloudToLocal: iCloud identifier → local identifier on this iPhone.
    /// - Returns: the state and how many photos were not found.
    public func restoredState(existing: Set<String>, cloudToLocal: [String: String]) -> (state: SweepState, missing: Int) {
        var missing = 0
        func resolve(_ ref: PhotoRef) -> String? {
            if existing.contains(ref.local) { return ref.local }
            if let cloud = ref.cloud, let local = cloudToLocal[cloud], existing.contains(local) { return local }
            missing += 1
            return nil
        }
        let kept = Set(kept.compactMap(resolve))
        let trash = trash.compactMap(resolve).filter { !kept.contains($0) }
        let state = SweepState(kept: kept, trash: trash, deletedCount: deletedCount, freedBytes: freedBytes)
        return (state, missing)
    }

    // MARK: Encoding

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        struct Header: Decodable { var app: String?; var version: Int? }
        guard let header = try? d.decode(Header.self, from: data) else { throw BackupError.unreadable }
        guard header.app == appName else { throw BackupError.wrongApp }
        guard let version = header.version, version <= currentVersion else { throw BackupError.tooNew }
        do {
            return try d.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, app, exportedAt, kept, trash, deletedCount, freedBytes, albums, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        app = try c.decode(String.self, forKey: .app)
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date(timeIntervalSince1970: 0)
        kept = try c.decodeIfPresent([PhotoRef].self, forKey: .kept) ?? []
        trash = try c.decodeIfPresent([PhotoRef].self, forKey: .trash) ?? []
        deletedCount = try c.decodeIfPresent(Int.self, forKey: .deletedCount) ?? 0
        freedBytes = try c.decodeIfPresent(Int64.self, forKey: .freedBytes) ?? 0
        albums = try c.decodeIfPresent([AlbumSummary].self, forKey: .albums) ?? []
        settings = try c.decodeIfPresent(SweepSettings.self, forKey: .settings) ?? SweepSettings()
    }
}

public enum BackupError: Error, Equatable, LocalizedError {
    case wrongApp
    case tooNew
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .wrongApp: return "Questo file non è un backup di Sweep."
        case .tooNew: return "Il backup è di una versione più recente di Sweep: aggiorna l'app."
        case .unreadable: return "Backup non leggibile."
        }
    }
}

/// Automatic backups in iCloud Drive: shared container
/// `iCloud.com.garoth93.backup`, sub-folder "Sweep", visible in Files as
/// iCloud Drive › Backup › Sweep.
///
/// Files: `Sweep-backup-yyyy-MM-dd.json` (one per day, overwritten during
/// the day, the last `keepDaily` kept) and `Sweep-backup-latest.json`.
public enum CloudBackupPlan {
    public static let containerID = "iCloud.com.garoth93.backup"
    public static let folderName = "Sweep"
    public static let latestName = "Sweep-backup-latest.json"
    public static let prefix = "Sweep-backup-"
    public static let keepDaily = 30

    public struct Entry: Equatable, Hashable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        /// Day of the backup (nil for "latest").
        public var day: Date?
        public var isLatest: Bool { day == nil }

        public init(name: String, day: Date?) {
            self.name = name
            self.day = day
        }
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func dailyName(for date: Date) -> String {
        "\(prefix)\(dayFormatter().string(from: date)).json"
    }

    /// Name for a manual export: `Sweep-backup-yyyy-MM-dd.json`.
    public static func exportName(for date: Date) -> String {
        dailyName(for: date)
    }

    /// iCloud placeholder of a file not downloaded yet: ".name.json.icloud".
    public static func realName(_ fileName: String) -> String {
        guard fileName.hasPrefix("."), fileName.hasSuffix(".icloud") else { return fileName }
        return String(fileName.dropFirst().dropLast(".icloud".count))
    }

    /// Backups found in the folder, newest first ("latest" on top).
    public static func entries(fromFileNames names: [String]) -> [Entry] {
        let f = dayFormatter()
        var latest: Entry?
        var daily: [Entry] = []
        for raw in Set(names.map(realName)) {
            if raw == latestName {
                latest = Entry(name: raw, day: nil)
            } else if raw.hasPrefix(prefix), raw.hasSuffix(".json") {
                let stamp = String(raw.dropFirst(prefix.count).dropLast(5))
                if let d = f.date(from: stamp) { daily.append(Entry(name: raw, day: d)) }
            }
        }
        daily.sort { ($0.day ?? .distantPast) > ($1.day ?? .distantPast) }
        return (latest.map { [$0] } ?? []) + daily
    }

    /// Daily files beyond the newest `keep`.
    public static func namesToPrune(_ names: [String], keep: Int = keepDaily) -> [String] {
        let daily = entries(fromFileNames: names).filter { !$0.isLatest }
        return daily.count > keep ? daily[keep...].map(\.name) : []
    }

    /// Fingerprint of what a backup contains, not of when it was made: an
    /// unchanged fingerprint means no new backup is needed.
    public static func fingerprint(_ backup: BackupFile) -> String {
        var b = backup
        b.exportedAt = Date(timeIntervalSince1970: 0)
        guard let data = try? b.encoded() else { return "" }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16) + "-" + String(data.count)
    }
}
