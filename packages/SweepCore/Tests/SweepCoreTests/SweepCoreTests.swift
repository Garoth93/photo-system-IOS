import Foundation
import XCTest
@testable import SweepCore

final class ReviewSessionTests: XCTestCase {
    func testDecideAndUndo() {
        var s = ReviewSession(ids: ["a", "b", "c"])
        XCTAssertEqual(s.current, "a")
        XCTAssertEqual(s.upcoming(2), ["a", "b"])
        XCTAssertFalse(s.canUndo)

        XCTAssertEqual(s.decide(.keep), .init(id: "a", move: .keep))
        XCTAssertEqual(s.decide(.delete), .init(id: "b", move: .delete))
        XCTAssertEqual(s.current, "c")
        XCTAssertEqual(s.keptCount, 1)
        XCTAssertEqual(s.deletedCount, 1)
        XCTAssertEqual(s.remaining, 1)
        XCTAssertEqual(s.progress, 2.0 / 3.0, accuracy: 1e-9)

        XCTAssertEqual(s.undo(), .init(id: "b", move: .delete))
        XCTAssertEqual(s.current, "b")
        XCTAssertEqual(s.deletedCount, 0)

        s.decide(.keep)
        s.decide(.keep)
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.current)
        XCTAssertNil(s.decide(.keep))
        XCTAssertEqual(s.upcoming(3), [])
        XCTAssertEqual(s.progress, 1)
    }

    func testEmptySession() {
        var s = ReviewSession(ids: [])
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.undo())
        XCTAssertEqual(s.progress, 1)
    }
}

final class SweepStateTests: XCTestCase {
    func testApplyAndRevert() {
        var st = SweepState()
        st.apply(.keep, to: "a")
        st.apply(.delete, to: "b")
        st.apply(.delete, to: "b")
        XCTAssertEqual(st.kept, ["a"])
        XCTAssertEqual(st.trash, ["b"])
        XCTAssertEqual(st.unreviewed(["a", "b", "c"]), ["c"])
        XCTAssertEqual(st.reviewedCount(of: ["a", "b", "c"]), 2)

        // Changing idea moves the photo between kept and bin.
        st.apply(.delete, to: "a")
        XCTAssertEqual(st.kept, [])
        XCTAssertEqual(st.trash, ["b", "a"])

        st.revert("a")
        XCTAssertEqual(st.trash, ["b"])
        XCTAssertFalse(st.isReviewed("a"))
    }

    func testRestoreKeepAndCommit() {
        var st = SweepState(trash: ["a", "b", "c", "a"])
        XCTAssertEqual(st.trash, ["a", "b", "c"])
        st.restore(["a"])
        st.keep(["b"])
        XCTAssertEqual(st.trash, ["c"])
        XCTAssertEqual(st.kept, ["b"])

        st.apply(.delete, to: "d")
        st.commitDeletion(of: ["c", "d"], bytes: 5_000_000)
        XCTAssertEqual(st.trash, [])
        XCTAssertEqual(st.deletedCount, 2)
        XCTAssertEqual(st.freedBytes, 5_000_000)
    }

    func testForgetAndPrune() {
        var st = SweepState(kept: ["a", "b", "c"], trash: ["x", "y"])
        st.forget(["a"])
        XCTAssertEqual(st.kept, ["b", "c"])
        st.prune(existing: ["b", "y"])
        XCTAssertEqual(st.kept, ["b"])
        XCTAssertEqual(st.trash, ["y"])
        st.forgetAllKept()
        XCTAssertTrue(st.kept.isEmpty)
        XCTAssertEqual(st.trash, ["y"])
    }

    func testJSONRoundTripAndMissingKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<SweepState>(url: dir.appendingPathComponent("state.json"))
        XCTAssertNil(try store.load())

        let st = SweepState(kept: ["k1", "k2"], trash: ["t1"], deletedCount: 3, freedBytes: 42)
        try store.save(st)
        XCTAssertEqual(try store.load(), st)

        let partial = Data(#"{"trash":["z"]}"#.utf8)
        let decoded = try JSONDecoder().decode(SweepState.self, from: partial)
        XCTAssertEqual(decoded, SweepState(trash: ["z"]))
    }
}

final class FormatTests: XCTestCase {
    func testCount() {
        XCTAssertEqual(SweepFormat.count(0), "0")
        XCTAssertEqual(SweepFormat.count(999), "999")
        XCTAssertEqual(SweepFormat.count(1234), "1.234")
        XCTAssertEqual(SweepFormat.count(1234567), "1.234.567")
        XCTAssertEqual(SweepFormat.photos(1), "1 foto")
    }

    func testBytes() {
        XCTAssertEqual(SweepFormat.bytes(0), "0 B")
        XCTAssertEqual(SweepFormat.bytes(820_400), "820 KB")
        XCTAssertEqual(SweepFormat.bytes(12_400_000), "12,4 MB")
        XCTAssertEqual(SweepFormat.bytes(3_000_000), "3 MB")
        XCTAssertEqual(SweepFormat.bytes(1_250_000_000), "1,25 GB")
        XCTAssertEqual(SweepFormat.bytes(2_050_000_000), "2,05 GB")
    }

    func testDuration() {
        XCTAssertEqual(SweepFormat.duration(7), "0:07")
        XCTAssertEqual(SweepFormat.duration(750), "12:30")
        XCTAssertEqual(SweepFormat.duration(3723), "1:02:03")
    }

    func testOrder() {
        XCTAssertEqual(SweepOrder.oldestFirst.arrange(newestFirst: ["c", "b", "a"]), ["a", "b", "c"])
        XCTAssertEqual(SweepOrder.random.arrange(newestFirst: ["c", "b", "a"]).sorted(), ["a", "b", "c"])
    }

    func testPalette() {
        let light = MaterialScheme(seed: Palette.defaultAccent, dark: false)
        let dark = MaterialScheme(seed: Palette.defaultAccent, dark: true)
        XCTAssertNotEqual(light.primary, dark.primary)
        XCTAssertEqual(RGBColor(hex: "#00796b")?.hex, "#00796b")
    }
}
