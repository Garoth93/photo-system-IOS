import Foundation
import Observation
import Photos
import SweepCore

/// File sizes of the library items, for the "heaviest first" order.
///
/// Reading a size asks Photos for the item's resources, which is slow on
/// big libraries: sizes are computed once, off the main thread, and cached
/// in Application Support/Sweep/sizes.json.
@MainActor
@Observable
final class SizeIndex {
    static let shared = SizeIndex()

    /// Progress of the current computation (nil when idle).
    private(set) var progress: (done: Int, total: Int)?

    @ObservationIgnored private var cache: [String: Int64]?
    @ObservationIgnored private let store: JSONFileStore<[String: Int64]>

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        store = JSONFileStore(url: base.appendingPathComponent("Sweep", isDirectory: true).appendingPathComponent("sizes.json"))
    }

    /// Sizes in bytes of the given items (from the cache, the missing ones computed now).
    func sizes(for ids: [String]) async -> [String: Int64] {
        if cache == nil {
            let store = self.store
            cache = await Task.detached(priority: .userInitiated) { (try? store.load()) ?? [:] }.value
        }
        var known = cache ?? [:]
        let missing = ids.filter { known[$0] == nil }
        if !missing.isEmpty {
            progress = (0, missing.count)
            let found = await Task.detached(priority: .userInitiated) { [weak self] in
                Self.compute(missing) { done in
                    Task { @MainActor in self?.progress = (done, missing.count) }
                }
            }.value
            known.merge(found) { _, new in new }
            cache = known
            progress = nil
            save()
        }
        return known
    }

    /// Items deleted from the library: drop them from the cache.
    func forget(_ ids: [String]) {
        guard var known = cache, !ids.isEmpty else { return }
        for id in ids { known[id] = nil }
        cache = known
        save()
    }

    private func save() {
        guard let snapshot = cache else { return }
        let store = self.store
        Task.detached(priority: .utility) { try? store.save(snapshot) }
    }

    nonisolated private static func compute(_ ids: [String], progress: @escaping @Sendable (Int) -> Void) -> [String: Int64] {
        var out: [String: Int64] = [:]
        var start = 0
        while start < ids.count {
            let chunk = Array(ids[start..<min(start + 300, ids.count)])
            autoreleasepool {
                PHAsset.fetchAssets(withLocalIdentifiers: chunk, options: nil).enumerateObjects { asset, _, _ in
                    out[asset.localIdentifier] = PhotoLibrary.fileSize(of: asset)
                }
            }
            start += chunk.count
            progress(start)
        }
        return out
    }
}
