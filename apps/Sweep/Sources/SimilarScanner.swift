import CoreGraphics
import Foundation
import Observation
import Photos
import SweepCore
import UIKit

/// Finds duplicates and similar shots in the library.
///
/// For every photo a 64-bit dHash is computed from a tiny local thumbnail
/// (no iCloud download) and cached in Application Support/Sweep/hashes.json,
/// so only new photos are hashed on the next scans. Grouping is pure logic
/// in `SweepCore.Similarity`.
@MainActor
@Observable
final class SimilarScanner {
    static let shared = SimilarScanner()

    enum Phase: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case ready
    }

    private(set) var phase: Phase = .idle
    /// All the groups of the last scan (use `Similarity.pending` to hide
    /// the ones already handled).
    private(set) var groups: [SimilarGroup] = []
    private(set) var lastScan: Date?

    @ObservationIgnored private let store: JSONFileStore<[String: String]>

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        store = JSONFileStore(url: base.appendingPathComponent("Sweep", isDirectory: true).appendingPathComponent("hashes.json"))
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    /// Scans the library (new photos only are hashed). Keeps running if the
    /// screen is closed; calling it again while scanning does nothing.
    func scan() async {
        guard PhotoLibrary.shared.canRead, !isScanning else { return }
        phase = .scanning(done: 0, total: 0)
        let store = self.store
        let result = await Task.detached(priority: .userInitiated) { [weak self] in
            let known = ((try? store.load()) ?? [:]).compactMapValues(Similarity.hash(hex:))
            let result = Self.compute(known: known) { done, total in
                Task { @MainActor in self?.phase = .scanning(done: done, total: total) }
            }
            try? store.save(result.hashes.mapValues(Similarity.hex))
            return result
        }.value
        groups = Similarity.groups(result.signatures)
        lastScan = Date()
        phase = .ready
    }

    private struct ScanResult: Sendable {
        var signatures: [PhotoSignature]
        var hashes: [String: UInt64]
    }

    nonisolated private static func compute(known: [String: UInt64],
                                            progress: @escaping @Sendable (Int, Int) -> Void) -> ScanResult {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeHiddenAssets = false
        let assets = PHAsset.fetchAssets(with: options)
        let total = assets.count
        progress(0, total)

        let manager = PHImageManager.default()
        let request = PHImageRequestOptions()
        request.isSynchronous = true
        request.deliveryMode = .fastFormat
        request.resizeMode = .fast
        request.isNetworkAccessAllowed = false
        request.version = .current

        var signatures: [PhotoSignature] = []
        signatures.reserveCapacity(total)
        var hashes: [String: UInt64] = [:]
        for index in 0..<total {
            let asset = assets.object(at: index)
            let id = asset.localIdentifier
            let hash = known[id] ?? autoreleasepool { () -> UInt64? in
                var image: UIImage?
                manager.requestImage(for: asset, targetSize: CGSize(width: 64, height: 64),
                                     contentMode: .aspectFit, options: request) { result, _ in image = result }
                return image?.cgImage.flatMap(grayHash)
            }
            if let hash {
                hashes[id] = hash
                signatures.append(PhotoSignature(id: id, date: asset.creationDate, hash: hash,
                                                 width: asset.pixelWidth, height: asset.pixelHeight,
                                                 isFavorite: asset.isFavorite))
            }
            if index % 150 == 0 || index == total - 1 { progress(index + 1, total) }
        }
        return ScanResult(signatures: signatures, hashes: hashes)
    }

    /// Draws the image into a 9×8 grayscale bitmap and hashes it.
    nonisolated static func grayHash(_ image: CGImage) -> UInt64? {
        let width = Similarity.hashWidth, height = Similarity.hashHeight
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Similarity.dHash(gray: pixels) : nil
    }
}
