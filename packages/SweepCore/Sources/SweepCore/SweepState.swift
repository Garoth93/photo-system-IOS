import Foundation

/// What the user decided for one photo.
public enum Decision: String, Codable, Sendable {
    /// Swipe left: keep the photo and move on.
    case keep
    /// Swipe right: put the photo in the bin and move on.
    case delete
}

/// Persistent memory of the cleanup, saved as JSON in Application Support.
///
/// Photos are identified by their `PHAsset.localIdentifier`.
/// - `kept`: photos already reviewed and kept; they are skipped in every album.
/// - `trash`: photos swiped to the right, waiting for the real deletion
///   (iOS asks for one confirmation per deletion request, so they are deleted
///   together with a single confirmation).
public struct SweepState: Codable, Equatable, Sendable {
    public var kept: Set<String>
    /// Ordered by the moment they were swiped, without duplicates.
    public private(set) var trash: [String]
    /// Total photos really deleted from the library through the app.
    public var deletedCount: Int
    /// Total bytes freed by those deletions (estimate from the file sizes).
    public var freedBytes: Int64

    public init(kept: Set<String> = [], trash: [String] = [], deletedCount: Int = 0, freedBytes: Int64 = 0) {
        self.kept = kept
        self.trash = []
        self.deletedCount = deletedCount
        self.freedBytes = freedBytes
        for id in trash where !self.trash.contains(id) { self.trash.append(id) }
    }

    // MARK: Queries

    public var trashCount: Int { trash.count }

    public func isInTrash(_ id: String) -> Bool { trash.contains(id) }

    public func isReviewed(_ id: String) -> Bool { kept.contains(id) || trash.contains(id) }

    /// The ids still to review, in the given order.
    public func unreviewed(_ ids: [String]) -> [String] {
        let binned = Set(trash)
        return ids.filter { !kept.contains($0) && !binned.contains($0) }
    }

    /// How many of `ids` were already reviewed (kept or binned).
    public func reviewedCount(of ids: [String]) -> Int {
        ids.count - unreviewed(ids).count
    }

    // MARK: Changes

    /// Records a swipe.
    public mutating func apply(_ decision: Decision, to id: String) {
        switch decision {
        case .keep:
            trash.removeAll { $0 == id }
            kept.insert(id)
        case .delete:
            kept.remove(id)
            if !trash.contains(id) { trash.append(id) }
        }
    }

    /// Undoes a swipe: the photo goes back to "not reviewed".
    public mutating func revert(_ id: String) {
        kept.remove(id)
        trash.removeAll { $0 == id }
    }

    /// Takes photos out of the bin; they will be proposed again.
    public mutating func restore<S: Sequence>(_ ids: S) where S.Element == String {
        let set = Set(ids)
        trash.removeAll { set.contains($0) }
    }

    /// Takes photos out of the bin and marks them as kept.
    public mutating func keep<S: Sequence>(_ ids: S) where S.Element == String {
        let set = Set(ids)
        trash.removeAll { set.contains($0) }
        kept.formUnion(set)
    }

    /// Call after the library confirmed the deletion of `ids`.
    public mutating func commitDeletion(of ids: [String], bytes: Int64) {
        let set = Set(ids)
        trash.removeAll { set.contains($0) }
        kept.subtract(set)
        deletedCount += set.count
        freedBytes += max(0, bytes)
    }

    /// "Review again": forgets that these photos were kept.
    public mutating func forget<S: Sequence>(_ ids: S) where S.Element == String {
        kept.subtract(ids)
    }

    /// Forgets every kept photo (the bin is left untouched).
    public mutating func forgetAllKept() {
        kept.removeAll()
    }

    /// Drops ids that no longer exist in the library (deleted elsewhere).
    public mutating func prune(existing: Set<String>) {
        kept.formIntersection(existing)
        trash.removeAll { !existing.contains($0) }
    }

    // MARK: Codable (tolerant to missing keys, so old files keep loading)

    private enum CodingKeys: String, CodingKey {
        case kept, trash, deletedCount, freedBytes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kept: try c.decodeIfPresent(Set<String>.self, forKey: .kept) ?? [],
            trash: try c.decodeIfPresent([String].self, forKey: .trash) ?? [],
            deletedCount: try c.decodeIfPresent(Int.self, forKey: .deletedCount) ?? 0,
            freedBytes: try c.decodeIfPresent(Int64.self, forKey: .freedBytes) ?? 0
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kept.sorted(), forKey: .kept)
        try c.encode(trash, forKey: .trash)
        try c.encode(deletedCount, forKey: .deletedCount)
        try c.encode(freedBytes, forKey: .freedBytes)
    }
}
