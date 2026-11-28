import Foundation
import XCTest
@testable import SweepCore

/// Synthetic data only (identifiers like "TEST-…").
final class SimilarityTests: XCTestCase {
    /// 9×8 gradient-like synthetic image; `seed` changes the pattern.
    private func image(_ seed: Int, noise: [Int: Int] = [:]) -> [UInt8] {
        (0..<72).map { i in
            let base = (i * 37 + seed * 101) % 251
            return UInt8(clamping: base + (noise[i] ?? 0))
        }
    }

    private func sig(_ id: String, _ hash: UInt64, at seconds: TimeInterval?, w: Int = 4000, h: Int = 3000,
                     favorite: Bool = false, bytes: Int64 = 1_000) -> PhotoSignature {
        PhotoSignature(id: id, date: seconds.map { Date(timeIntervalSince1970: 1_700_000_000 + $0) },
                       hash: hash, width: w, height: h, isFavorite: favorite, bytes: bytes)
    }

    func testDHash() throws {
        XCTAssertNil(Similarity.dHash(gray: [1, 2, 3]))
        let flat = [UInt8](repeating: 128, count: 72)
        XCTAssertEqual(Similarity.dHash(gray: flat), 0)
        let decreasing = (0..<72).map { UInt8(255 - ($0 % 9) * 20) }
        XCTAssertEqual(Similarity.dHash(gray: decreasing), UInt64.max)

        let a = try XCTUnwrap(Similarity.dHash(gray: image(1)))
        let slightlyDifferent = try XCTUnwrap(Similarity.dHash(gray: image(1, noise: [10: 3])))
        let other = try XCTUnwrap(Similarity.dHash(gray: image(7)))
        XCTAssertLessThanOrEqual(Similarity.distance(a, slightlyDifferent), 2)
        XCTAssertGreaterThan(Similarity.distance(a, other), 10)
        XCTAssertEqual(Similarity.hash(hex: Similarity.hex(a)), a)
    }

    func testGroupsByTimeAndByIdenticalHash() {
        let items = [
            // Burst: three shots in 20 seconds, almost the same picture.
            sig("TEST-B1", 0b1111_0000, at: 0, bytes: 2_000),
            sig("TEST-B2", 0b1111_0001, at: 10, bytes: 3_000),
            sig("TEST-B3", 0b1111_0011, at: 20, bytes: 1_000),
            // Same scene but an hour later and different: not grouped.
            sig("TEST-X", 0xFFFF_0000_FFFF, at: 3_600),
            // Close in time but a different picture.
            sig("TEST-Y", 0x0F0F_0F0F_0F0F_0F0F, at: 30),
            // The same picture saved again a year later (identical hash).
            sig("TEST-D1", 0xABCD_EF01, at: 100_000),
            sig("TEST-D2", 0xABCD_EF01, at: 31_000_000, favorite: true),
            // Identical hash but portrait vs landscape: not grouped.
            sig("TEST-P", 0xABCD_EF01, at: 50_000_000, w: 3000, h: 4000),
        ]
        let groups = Similarity.groups(items)
        XCTAssertEqual(groups.count, 2)

        let dup = groups[0]   // newest first
        XCTAssertEqual(dup.ids, ["TEST-D1", "TEST-D2"])
        XCTAssertEqual(dup.kind, .duplicates)
        XCTAssertEqual(dup.best, "TEST-D2")   // favourite wins

        let burst = groups[1]
        XCTAssertEqual(burst.ids, ["TEST-B1", "TEST-B2", "TEST-B3"])
        XCTAssertEqual(burst.best, "TEST-B2")   // same pixels: heavier file
        XCTAssertEqual(burst.kind, .duplicates)
    }

    func testChainedWindowAndSimilarKind() {
        let items = [
            sig("TEST-1", 0, at: 0),
            sig("TEST-2", 0b11_1111, at: 150),          // 6 bits from TEST-1
            sig("TEST-3", 0b1111_1111_1111, at: 300),   // 300 s after TEST-1, chained via TEST-2
        ]
        let groups = Similarity.groups(items, window: 180, similar: 10, duplicate: 3)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].ids, ["TEST-1", "TEST-2", "TEST-3"])
        XCTAssertEqual(groups[0].kind, .similar)
        XCTAssertTrue(Similarity.groups([sig("TEST-1", 0, at: 0)]).isEmpty)
    }

    func testBestPrefersMorePixels() {
        let items = [sig("TEST-S", 1, at: 0, w: 1000, h: 750, bytes: 9_000), sig("TEST-L", 1, at: 1, w: 4000, h: 3000)]
        XCTAssertEqual(Similarity.best(of: items), "TEST-L")
    }

    func testPendingDropsBinnedAndFullyKeptGroups() {
        let groups = [
            SimilarGroup(ids: ["TEST-A", "TEST-B", "TEST-C"], kind: .similar, best: "TEST-A", date: nil),
            SimilarGroup(ids: ["TEST-D", "TEST-E"], kind: .duplicates, best: "TEST-D", date: nil),
            SimilarGroup(ids: ["TEST-F", "TEST-G"], kind: .duplicates, best: "TEST-F", date: nil),
        ]
        var state = SweepState()
        state.apply(.delete, to: "TEST-A")       // best in the bin → new best
        state.apply(.delete, to: "TEST-E")       // only one left → hidden
        state.apply(.keep, to: "TEST-F")
        state.apply(.keep, to: "TEST-G")         // all kept → hidden
        let pending = Similarity.pending(groups, state: state)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].ids, ["TEST-B", "TEST-C"])
        XCTAssertEqual(pending[0].best, "TEST-B")
    }
}
