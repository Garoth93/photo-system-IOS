import AVFoundation
import Observation
import Photos
import SweepCore
import UIKit

/// What is being cleaned: the whole library or one album.
enum SweepSource: Hashable, Identifiable {
    case library
    /// Every video, heaviest first (whatever the media filter is).
    case largeVideos
    case album(id: String, title: String, icon: String)

    var id: String {
        switch self {
        case .library: return "library"
        case .largeVideos: return "largeVideos"
        case .album(let id, _, _): return id
        }
    }

    var title: String {
        switch self {
        case .library: return "Tutte le foto"
        case .largeVideos: return "Video più pesanti"
        case .album(_, let title, _): return title
        }
    }

    var icon: String {
        switch self {
        case .library: return "photo.on.rectangle.angled"
        case .largeVideos: return "film.stack"
        case .album(_, _, let icon): return icon
        }
    }
}

/// One album with the ids of its items (newest first, current media filter).
struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let ids: [String]

    var source: SweepSource { .album(id: id, title: title, icon: icon) }
}

/// Details shown on the photo card.
struct AssetInfo: Equatable {
    var date: Date?
    var isVideo: Bool
    var duration: Double
    var isFavorite: Bool
    var isScreenshot: Bool
    var isLivePhoto: Bool
    var pixelWidth: Int
    var pixelHeight: Int
}

/// Thin wrapper around the Photos framework.
@Observable
@MainActor
final class PhotoLibrary {
    static let shared = PhotoLibrary()

    private(set) var status: PHAuthorizationStatus
    private(set) var libraryIDs: [String] = []
    private(set) var collections: [AlbumInfo] = []   // smart albums (Screenshots, Selfie…)
    private(set) var albums: [AlbumInfo] = []        // user albums
    private(set) var videoCount = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Bumped every time the library changes (also outside the app).
    private(set) var changeCount = 0

    @ObservationIgnored let imageManager = PHCachingImageManager()
    @ObservationIgnored private var relay: ChangeRelay?
    @ObservationIgnored private var assetCache: [String: PHAsset] = [:]

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        startObservingIfAllowed()
    }

    var canRead: Bool { status == .authorized || status == .limited }
    var isLimited: Bool { status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        startObservingIfAllowed()
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        startObservingIfAllowed()
    }

    private func startObservingIfAllowed() {
        guard canRead, relay == nil else { return }
        let relay = ChangeRelay { [weak self] in
            Task { @MainActor in
                self?.assetCache.removeAll()
                self?.changeCount += 1
            }
        }
        PHPhotoLibrary.shared().register(relay)
        self.relay = relay
    }

    // MARK: Albums

    func reload(filter: MediaFilter) async {
        guard canRead else { return }
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) {
            Self.loadAll(filter: filter)
        }.value
        libraryIDs = result.library
        collections = result.collections
        albums = result.albums
        videoCount = result.videoCount
        isLoading = false
        hasLoaded = true
    }

    private struct LoadResult: Sendable {
        let library: [String]
        let collections: [AlbumInfo]
        let albums: [AlbumInfo]
        let videoCount: Int
    }

    nonisolated private static func loadAll(filter: MediaFilter) -> LoadResult {
        let library = Self.ids(in: PHAsset.fetchAssets(with: Self.fetchOptions(filter)))

        let smart: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumScreenshots, "camera.viewfinder"),
            (.smartAlbumSelfPortraits, "person.crop.square"),
            (.smartAlbumVideos, "video"),
            (.smartAlbumLivePhotos, "livephoto"),
            (.smartAlbumBursts, "square.stack.3d.down.right"),
            (.smartAlbumPanoramas, "pano"),
            (.smartAlbumSlomoVideos, "slowmo"),
            (.smartAlbumTimelapses, "timelapse"),
            (.smartAlbumFavorites, "heart")
        ]
        var collections: [AlbumInfo] = []
        for (subtype, icon) in smart {
            let fetched = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            guard let collection = fetched.firstObject else { continue }
            let itemIDs = Self.ids(in: PHAsset.fetchAssets(in: collection, options: Self.fetchOptions(filter)))
            guard !itemIDs.isEmpty else { continue }
            collections.append(AlbumInfo(id: collection.localIdentifier, title: collection.localizedTitle ?? "Raccolta", icon: icon, ids: itemIDs))
        }

        var albums: [AlbumInfo] = []
        let user = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        user.enumerateObjects { collection, _, _ in
            let itemIDs = Self.ids(in: PHAsset.fetchAssets(in: collection, options: Self.fetchOptions(filter)))
            guard !itemIDs.isEmpty else { return }
            albums.append(AlbumInfo(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album", icon: "rectangle.stack", ids: itemIDs))
        }
        albums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let videoCount = PHAsset.fetchAssets(with: Self.fetchOptions(.videos)).count
        return LoadResult(library: library, collections: collections, albums: albums, videoCount: videoCount)
    }

    nonisolated private static func fetchOptions(_ filter: MediaFilter) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        switch filter {
        case .all:
            options.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        case .photos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }
        return options
    }

    nonisolated private static func ids(in result: PHFetchResult<PHAsset>) -> [String] {
        var ids: [String] = []
        ids.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }

    /// Ids of a source, newest first (re-fetched, so always up to date).
    func ids(for source: SweepSource, filter: MediaFilter) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            switch source {
            case .library:
                return Self.ids(in: PHAsset.fetchAssets(with: Self.fetchOptions(filter)))
            case .largeVideos:
                return Self.ids(in: PHAsset.fetchAssets(with: Self.fetchOptions(.videos)))
            case .album(let id, _, _):
                guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else {
                    return []
                }
                return Self.ids(in: PHAsset.fetchAssets(in: collection, options: Self.fetchOptions(filter)))
            }
        }.value
    }

    /// Every item of the library (photos and videos), local identifiers.
    func allLocalIDs() async -> Set<String> {
        Set(await ids(for: .library, filter: .all))
    }

    // MARK: iCloud Photos identifiers (for backups that survive a new iPhone)

    /// Local identifier → iCloud Photos identifier (only for items in iCloud Photos).
    func cloudIdentifiers(for locals: [String]) async -> [String: String] {
        guard canRead, !locals.isEmpty else { return [:] }
        return await Task.detached(priority: .utility) {
            var out: [String: String] = [:]
            let library = PHPhotoLibrary.shared()
            var start = 0
            while start < locals.count {
                let chunk = Array(locals[start..<min(start + 500, locals.count)])
                for (local, result) in library.cloudIdentifierMappings(forLocalIdentifiers: chunk) {
                    if case .success(let cloud) = result { out[local] = cloud.stringValue }
                }
                start += 500
            }
            return out
        }.value
    }

    /// iCloud Photos identifier → local identifier on this iPhone.
    func localIdentifiers(forCloud cloudIDs: [String]) async -> [String: String] {
        guard canRead, !cloudIDs.isEmpty else { return [:] }
        return await Task.detached(priority: .userInitiated) {
            var out: [String: String] = [:]
            let library = PHPhotoLibrary.shared()
            var start = 0
            while start < cloudIDs.count {
                let chunk = cloudIDs[start..<min(start + 500, cloudIDs.count)].map { PHCloudIdentifier(stringValue: $0) }
                for (cloud, result) in library.localIdentifierMappings(for: chunk) {
                    if case .success(let local) = result { out[cloud.stringValue] = local }
                }
                start += 500
            }
            return out
        }.value
    }

    // MARK: Assets

    func asset(_ id: String) -> PHAsset? {
        if let cached = assetCache[id] { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        if assetCache.count > 400 { assetCache.removeAll() }
        assetCache[id] = asset
        return asset
    }

    func info(for id: String) -> AssetInfo? {
        guard let a = asset(id) else { return nil }
        return AssetInfo(
            date: a.creationDate,
            isVideo: a.mediaType == .video,
            duration: a.duration,
            isFavorite: a.isFavorite,
            isScreenshot: a.mediaSubtypes.contains(.photoScreenshot),
            isLivePhoto: a.mediaSubtypes.contains(.photoLive),
            pixelWidth: a.pixelWidth,
            pixelHeight: a.pixelHeight
        )
    }

    /// Image for `id`: a quick low-quality version first, then the sharp one.
    func images(for id: String, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFit) -> AsyncStream<UIImage> {
        let asset = asset(id)
        let manager = imageManager
        return AsyncStream { continuation in
            guard let asset else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            options.version = .current
            let request = manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded || image == nil { continuation.finish() }
            }
            continuation.onTermination = { _ in
                manager.cancelImageRequest(request)
            }
        }
    }

    /// Adds or removes the heart in Photos.
    @discardableResult
    func setFavorite(_ id: String, _ value: Bool) async -> Bool {
        guard let asset = asset(id), asset.isFavorite != value else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).isFavorite = value
            }
            assetCache[id] = nil
            return true
        } catch {
            return false
        }
    }

    /// Warms the cache for the next photos of the queue.
    func preheat(_ ids: [String], targetSize: CGSize) {
        let assets = ids.compactMap { asset($0) }
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFit, options: options)
    }

    func stopPreheating() {
        imageManager.stopCachingImagesForAllAssets()
    }

    func playerItem(for id: String) async -> AVPlayerItem? {
        guard let asset = asset(id), asset.mediaType == .video else { return nil }
        let manager = imageManager
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    // MARK: Sizes and deletion

    /// Total size on disk of the given items (all resources, e.g. Live Photo video too).
    func totalSize(of ids: [String]) async -> Int64 {
        guard !ids.isEmpty else { return 0 }
        return await Task.detached(priority: .utility) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var total: Int64 = 0
            assets.enumerateObjects { asset, _, _ in total += Self.fileSize(of: asset) }
            return total
        }.value
    }

    func fileSize(of id: String) async -> Int64 {
        await totalSize(of: [id])
    }

    nonisolated static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { sum, resource in
            let value = resource.value(forKey: "fileSize")
            if let n = value as? Int64 { return sum + n }
            if let n = value as? Int { return sum + Int64(n) }
            if let n = value as? NSNumber { return sum + n.int64Value }
            return sum
        }
    }

    struct DeletionResult {
        let deleted: [String]
        let missing: [String]
        let bytes: Int64
    }

    /// Deletes the items from the library. iOS shows its own confirmation;
    /// deleted items stay in "Eliminati di recente" for 30 days.
    func delete(ids: [String]) async throws -> DeletionResult {
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var found: [String] = []
        fetched.enumerateObjects { asset, _, _ in found.append(asset.localIdentifier) }
        let foundSet = Set(found)
        let missing = ids.filter { !foundSet.contains($0) }
        guard !found.isEmpty else { return DeletionResult(deleted: [], missing: missing, bytes: 0) }

        let bytes = await totalSize(of: found)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(fetched)
        }
        found.forEach { assetCache[$0] = nil }
        return DeletionResult(deleted: found, missing: missing, bytes: bytes)
    }

    /// True when the error only means "the user tapped Don't Allow".
    static func isUserCancel(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == PHPhotosErrorDomain && e.code == PHPhotosError.Code.userCancelled.rawValue { return true }
        return e.code == 3072
    }
}

/// Forwards Photos change notifications (the observer must be an NSObject).
private final class ChangeRelay: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange()
    }
}
