import BackgroundTasks
import Foundation
import Observation
import SweepCore
import UIKit

/// Automatic backups in iCloud Drive, in the shared container
/// `iCloud.com.garoth93.backup` › Documents › Sweep (visible in the Files app
/// as iCloud Drive › Backup › Sweep). One JSON per day (last 30) plus
/// "latest". Written a few seconds after the data change, when the app goes
/// to background and from the background refresh. Restore from Settings, or
/// guided at first launch when the app is empty.
///
/// The backup contains only Sweep's decisions (photo identifiers, album
/// progress, preferences): never photos, thumbnails, tokens or other
/// sensitive data.
@MainActor
@Observable
final class CloudBackupService {
    static let shared = CloudBackupService()
    static let refreshTaskID = "com.garoth93.sweep.backup"

    /// nil = not checked yet; false = iCloud off / not signed in / no entitlement.
    private(set) var available: Bool?
    private(set) var isWorking = false
    private(set) var lastBackupAt: Date?
    private(set) var lastError: String?
    private(set) var entries: [CloudBackupPlan.Entry] = []
    /// Set when an empty app finds a backup: RootView shows the guided restore.
    var offerRestore = false

    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var backgroundWork: UIBackgroundTaskIdentifier = .invalid
    /// Local identifier → iCloud Photos identifier, kept on disk to avoid
    /// asking Photos again for every backup.
    @ObservationIgnored private var cloudCache: [String: String] = [:]
    @ObservationIgnored private var cloudCacheLoaded = false
    /// Items without an iCloud identifier (iCloud Photos off): not asked again this session.
    @ObservationIgnored private var unmapped: Set<String> = []
    @ObservationIgnored private let cacheStore: JSONFileStore<[String: String]>

    private enum Keys {
        static let fingerprint = "cloudBackup.fingerprint"
        static let lastAt = "cloudBackup.lastAt"
        static let restoreOffered = "cloudBackup.restoreOffered"
    }

    private var model: AppModel { AppModel.shared }
    private var library: PhotoLibrary { PhotoLibrary.shared }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheStore = JSONFileStore(url: base.appendingPathComponent("Sweep", isDirectory: true).appendingPathComponent("cloud-ids.json"))
        lastBackupAt = UserDefaults.standard.object(forKey: Keys.lastAt) as? Date
        AppModel.shared.onDataChanged = { [weak self] in self?.schedule() }
    }

    // MARK: Folder

    /// Resolving the ubiquity container can block: always off the main thread.
    nonisolated static func folderURL() async -> URL? {
        await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: CloudBackupPlan.containerID) else { return nil }
            let folder = container.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(CloudBackupPlan.folderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }.value
    }

    // MARK: Building the file

    /// The backup of the current data (iCloud Photos identifiers included).
    func makeFile() async -> BackupFile {
        if library.canRead && !library.hasLoaded {
            await library.reload(filter: model.filter)
        }
        let state = model.state
        let ids = Array(state.kept) + state.trash
        let cloud = await cloudIdentifiers(for: ids)
        return BackupFile(state: state, settings: model.settings, albums: albumSummaries(state), cloudIDs: cloud)
    }

    private func albumSummaries(_ state: SweepState) -> [AlbumSummary] {
        guard library.hasLoaded else { return [] }
        var out = [AlbumSummary(title: "Tutte le foto", kind: "libreria", total: library.libraryIDs.count,
                                reviewed: state.reviewedCount(of: library.libraryIDs))]
        for album in library.collections {
            out.append(AlbumSummary(title: album.title, kind: "raccolta", total: album.ids.count, reviewed: state.reviewedCount(of: album.ids)))
        }
        for album in library.albums {
            out.append(AlbumSummary(title: album.title, kind: "album", total: album.ids.count, reviewed: state.reviewedCount(of: album.ids)))
        }
        return out
    }

    private func cloudIdentifiers(for ids: [String]) async -> [String: String] {
        if !cloudCacheLoaded {
            let store = cacheStore
            cloudCache = await Task.detached(priority: .utility) { (try? store.load()) ?? [:] }.value
            cloudCacheLoaded = true
        }
        let wanted = Set(ids)
        let missing = ids.filter { cloudCache[$0] == nil && !unmapped.contains($0) }
        var changed = false
        if !missing.isEmpty {
            let found = await library.cloudIdentifiers(for: missing)
            cloudCache.merge(found) { _, new in new }
            unmapped.formUnion(missing.filter { found[$0] == nil })
            changed = !found.isEmpty
        }
        // Forget the photos that left the app's memory (deleted, restored…).
        let before = cloudCache.count
        cloudCache = cloudCache.filter { wanted.contains($0.key) }
        if changed || cloudCache.count != before { saveCloudCache() }
        return cloudCache
    }

    private func saveCloudCache() {
        let snapshot = cloudCache
        let store = cacheStore
        Task.detached(priority: .utility) { try? store.save(snapshot) }
    }

    // MARK: Backup

    /// After a change: back up a few seconds later (many swipes → one write).
    func schedule() {
        guard model.cloudBackup else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await self?.backup(force: false)
        }
    }

    /// Writes the backup if the content changed since the last one (or `force`).
    /// An empty app never overwrites existing backups.
    @discardableResult
    func backup(force: Bool) async -> Bool {
        guard force || model.cloudBackup else { return false }
        guard model.hasData else {
            if force { lastError = "Non c'è ancora niente da salvare: scorri qualche foto." }
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        let file = await makeFile()
        let fp = CloudBackupPlan.fingerprint(file)
        if !force, fp == UserDefaults.standard.string(forKey: Keys.fingerprint) { return false }
        guard let data = try? file.encoded() else { return false }
        guard let folder = await Self.folderURL() else {
            available = false
            if force { lastError = "iCloud Drive non disponibile: controlla di aver fatto l'accesso a iCloud e che iCloud Drive sia attivo." }
            return false
        }
        available = true
        let now = file.exportedAt
        let failure = await Task.detached(priority: .utility) { () -> String? in
            do {
                try Self.coordinatedWrite(data, to: folder.appendingPathComponent(CloudBackupPlan.dailyName(for: now)))
                try Self.coordinatedWrite(data, to: folder.appendingPathComponent(CloudBackupPlan.latestName))
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for name in CloudBackupPlan.namesToPrune(names) {
                    Self.coordinatedDelete(folder.appendingPathComponent(name))
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let failure {
            lastError = "Backup su iCloud non riuscito: \(failure)"
            return false
        }
        lastError = nil
        lastBackupAt = now
        UserDefaults.standard.set(now, forKey: Keys.lastAt)
        UserDefaults.standard.set(fp, forKey: Keys.fingerprint)
        return true
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    nonisolated private static func coordinatedDelete(_ url: URL) {
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &err) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Downloads (if needed) and reads an iCloud file; nil after ~30 s.
    nonisolated private static func coordinatedRead(_ url: URL, attempts: Int = 60) async -> Data? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<attempts {
            var coordError: NSError?
            var out: Data?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { target in
                out = try? Data(contentsOf: target)
            }
            if let out { return out }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    // MARK: Background

    /// App going to background: last backup with a little extra time, and
    /// the next background refresh.
    func appDidEnterBackground() {
        scheduleBackgroundRefresh()
        guard model.cloudBackup, model.hasData else { return }
        scheduled?.cancel()
        backgroundWork = UIApplication.shared.beginBackgroundTask(withName: "SweepBackup") {
            MainActor.assumeIsolated { CloudBackupService.shared.endBackgroundWork() }
        }
        Task {
            await backup(force: false)
            endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        guard backgroundWork != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundWork)
        backgroundWork = .invalid
    }

    /// Background refresh every ~6 hours (iOS decides the exact moment).
    func scheduleBackgroundRefresh() {
        guard model.cloudBackup else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    func runBackgroundRefresh() async {
        scheduleBackgroundRefresh()
        await backup(force: false)
    }

    // MARK: Restore

    /// Backups in the iCloud folder, newest first.
    func refreshEntries() async {
        guard let folder = await Self.folderURL() else {
            available = false
            entries = []
            return
        }
        available = true
        let names = await Task.detached(priority: .userInitiated) {
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        }.value
        entries = CloudBackupPlan.entries(fromFileNames: names)
    }

    func load(_ entry: CloudBackupPlan.Entry) async throws -> BackupFile {
        guard let folder = await Self.folderURL() else { throw BackupError.unreadable }
        let url = folder.appendingPathComponent(entry.name)
        guard let data = await Task.detached(priority: .userInitiated, operation: { await Self.coordinatedRead(url) }).value else {
            throw BackupError.unreadable
        }
        return try BackupFile.decode(data)
    }

    /// Replaces the app data with the backup. Photo identifiers are matched
    /// on this iPhone (directly, or through iCloud Photos on a new iPhone).
    /// Returns false on error (see `lastError`).
    @discardableResult
    func restore(_ file: BackupFile) async -> Bool {
        guard library.canRead else {
            lastError = "Per ripristinare serve l'accesso alle foto."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        scheduled?.cancel()
        let existing = await library.allLocalIDs()
        let cloudToLocal = await library.localIdentifiers(forCloud: file.cloudIDs)
        let result = file.restoredState(existing: existing, cloudToLocal: cloudToLocal)

        // The iCloud identifiers are already known: no need to ask Photos again.
        for (cloud, local) in cloudToLocal { cloudCache[local] = cloud }
        for ref in file.kept + file.trash where existing.contains(ref.local) {
            if let cloud = ref.cloud { cloudCache[ref.local] = cloud }
        }
        cloudCacheLoaded = true
        saveCloudCache()

        model.replace(state: result.state, settings: file.settings)
        lastError = nil
        let restored = result.state.kept.count + result.state.trashCount
        var message = "Ripristinate le scelte su \(SweepFormat.photos(restored))."
        if result.missing > 0 {
            message += " \(SweepFormat.photos(result.missing)) non sono più in questa libreria."
        }
        model.showToast(message)
        return true
    }

    @discardableResult
    func restore(_ entry: CloudBackupPlan.Entry) async -> Bool {
        do {
            let file = try await load(entry)
            return await restore(file)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: First launch

    /// Empty app + backups in iCloud → guided restore (asked once).
    func offerRestoreIfNeeded() async {
        guard library.canRead, !model.hasData, !UserDefaults.standard.bool(forKey: Keys.restoreOffered) else { return }
        await refreshEntries()
        guard !entries.isEmpty, !model.hasData else { return }
        UserDefaults.standard.set(true, forKey: Keys.restoreOffered)
        offerRestore = true
    }
}
