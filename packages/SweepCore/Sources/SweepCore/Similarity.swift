import Foundation

/// What Sweep knows about a photo to find duplicates and similar shots.
public struct PhotoSignature: Equatable, Sendable {
    public var id: String
    public var date: Date?
    /// 64-bit difference hash (dHash) of a 9×8 grayscale thumbnail.
    public var hash: UInt64
    public var width: Int
    public var height: Int
    public var isFavorite: Bool
    public var bytes: Int64

    public init(id: String, date: Date?, hash: UInt64, width: Int, height: Int,
                isFavorite: Bool = false, bytes: Int64 = 0) {
        self.id = id
        self.date = date
        self.hash = hash
        self.width = width
        self.height = height
        self.isFavorite = isFavorite
        self.bytes = bytes
    }

    var pixels: Int { width * height }
}

/// A set of photos that look the same (or almost).
public struct SimilarGroup: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        /// Practically identical (copies, saved twice, burst frames).
        case duplicates
        /// Same scene shot a few times in a row.
        case similar
    }

    /// Members in shooting order.
    public var ids: [String]
    public var kind: Kind
    /// Suggested photo to keep.
    public var best: String
    /// Date of the newest member.
    public var date: Date?

    public var id: String { ids.first ?? best }
}

/// Duplicate and similar-photo detection. Pure logic: the app provides the
/// grayscale thumbnails and the photo metadata.
public enum Similarity {
    public static let hashWidth = 9
    public static let hashHeight = 8

    /// dHash of a 9×8 grayscale image (row by row, 72 bytes): each bit says
    /// whether a pixel is brighter than its right neighbour. nil if the size
    /// is wrong.
    public static func dHash(gray: [UInt8]) -> UInt64? {
        guard gray.count == hashWidth * hashHeight else { return nil }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for row in 0..<hashHeight {
            for col in 0..<(hashWidth - 1) {
                let left = gray[row * hashWidth + col]
                let right = gray[row * hashWidth + col + 1]
                if left > right { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }

    /// Number of different bits (0 = same picture, 64 = opposite).
    public static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Same orientation and almost the same aspect ratio.
    static func sameShape(_ a: PhotoSignature, _ b: PhotoSignature) -> Bool {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return true }
        let ra = Double(a.width) / Double(a.height)
        let rb = Double(b.width) / Double(b.height)
        return abs(ra - rb) / max(ra, rb) < 0.05
    }

    /// The photo to suggest keeping: favourite first, then the one with
    /// more pixels, then the heavier file, then the newest.
    public static func best(of items: [PhotoSignature]) -> String? {
        items.max { a, b in
            if a.isFavorite != b.isFavorite { return !a.isFavorite }
            if a.pixels != b.pixels { return a.pixels < b.pixels }
            if a.bytes != b.bytes { return a.bytes < b.bytes }
            return (a.date ?? .distantPast) < (b.date ?? .distantPast)
        }?.id
    }

    /// Groups of duplicates / similar photos.
    /// - Photos shot within `window` seconds of each other (chained) with a
    ///   hash distance ≤ `similar` are grouped (bursts, repeated shots).
    /// - Photos with the same hash anywhere in the library are grouped too
    ///   (copies saved again, received twice).
    /// Groups have at least two photos and are sorted newest first.
    public static func groups(_ items: [PhotoSignature], window: TimeInterval = 180,
                              similar: Int = 10, duplicate: Int = 3,
                              maxNeighbors: Int = 40) -> [SimilarGroup] {
        guard items.count > 1 else { return [] }
        let sorted = items.enumerated().sorted { a, b in
            switch (a.element.date, b.element.date) {
            case let (x?, y?): return x != y ? x < y : a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)

        var parent = Array(0..<sorted.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }

        // Shots close in time.
        for i in 0..<sorted.count {
            guard let di = sorted[i].date else { continue }
            var j = i + 1
            while j < sorted.count, j <= i + maxNeighbors, let dj = sorted[j].date, dj.timeIntervalSince(di) <= window {
                if sameShape(sorted[i], sorted[j]), distance(sorted[i].hash, sorted[j].hash) <= similar {
                    union(i, j)
                }
                j += 1
            }
        }

        // Identical pictures anywhere in the library.
        var byHash: [UInt64: Int] = [:]
        for i in 0..<sorted.count {
            if let first = byHash[sorted[i].hash] {
                if sameShape(sorted[first], sorted[i]) { union(first, i) }
            } else {
                byHash[sorted[i].hash] = i
            }
        }

        var members: [Int: [Int]] = [:]
        for i in 0..<sorted.count { members[find(i), default: []].append(i) }

        var result: [SimilarGroup] = []
        for indexes in members.values where indexes.count > 1 {
            let photos = indexes.map { sorted[$0] }
            guard let bestID = best(of: photos), let bestPhoto = photos.first(where: { $0.id == bestID }) else { continue }
            let allClose = photos.allSatisfy { distance($0.hash, bestPhoto.hash) <= duplicate }
            result.append(SimilarGroup(
                ids: photos.map(\.id),
                kind: allClose ? .duplicates : .similar,
                best: bestID,
                date: photos.compactMap(\.date).max()
            ))
        }
        return result.sorted { a, b in
            let da = a.date ?? .distantPast, db = b.date ?? .distantPast
            return da != db ? da > db : a.id < b.id
        }
    }

    /// Groups still worth showing: members already in the bin are dropped,
    /// and a group is hidden once every remaining photo has been kept.
    public static func pending(_ groups: [SimilarGroup], state: SweepState) -> [SimilarGroup] {
        let binned = Set(state.trash)
        return groups.compactMap { group in
            var g = group
            g.ids = group.ids.filter { !binned.contains($0) }
            guard g.ids.count > 1, !g.ids.allSatisfy({ state.kept.contains($0) }) else { return nil }
            if !g.ids.contains(g.best) { g.best = g.ids[0] }
            return g
        }
    }

    /// Hex form used to cache hashes in JSON.
    public static func hex(_ hash: UInt64) -> String { String(hash, radix: 16) }
    public static func hash(hex: String) -> UInt64? { UInt64(hex, radix: 16) }
}
