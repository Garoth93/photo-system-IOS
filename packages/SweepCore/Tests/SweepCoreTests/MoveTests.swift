import Foundation
import XCTest
@testable import SweepCore

/// Synthetic data only (identifiers like "TEST-…").
final class MoveTests: XCTestCase {
    func testLaterMovesThePhotoToTheEndAndUndoRestoresIt() {
        var s = ReviewSession(ids: ["TEST-A", "TEST-B", "TEST-C"])
        XCTAssertEqual(s.apply(.later), .init(id: "TEST-A", move: .later))
        XCTAssertEqual(s.ids, ["TEST-B", "TEST-C", "TEST-A"])
        XCTAssertEqual(s.current, "TEST-B")
        XCTAssertEqual(s.position, 0)
        XCTAssertEqual(s.progress, 0)

        s.apply(.favorite)
        XCTAssertEqual(s.current, "TEST-C")
        XCTAssertEqual(s.keptCount, 1)
        XCTAssertEqual(s.favoriteCount, 1)

        s.apply(.later)
        XCTAssertEqual(s.ids, ["TEST-B", "TEST-A", "TEST-C"])
        XCTAssertEqual(s.current, "TEST-A")

        XCTAssertEqual(s.undo()?.move, .later)
        XCTAssertEqual(s.ids, ["TEST-B", "TEST-C", "TEST-A"])
        XCTAssertEqual(s.current, "TEST-C")
        XCTAssertEqual(s.undo()?.move, .favorite)
        XCTAssertEqual(s.current, "TEST-B")
        XCTAssertEqual(s.undo()?.move, .later)
        XCTAssertEqual(s.ids, ["TEST-A", "TEST-B", "TEST-C"])
        XCTAssertEqual(s.current, "TEST-A")
        XCTAssertFalse(s.canUndo)
    }

    func testLaterOnTheLastPhotoKeepsItOnScreen() {
        var s = ReviewSession(ids: ["TEST-A"])
        s.apply(.later)
        XCTAssertEqual(s.current, "TEST-A")
        XCTAssertFalse(s.isFinished)
        s.apply(.delete)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.deletedCount, 1)
    }

    func testMoveDecisions() {
        XCTAssertEqual(Move.keep.decision, .keep)
        XCTAssertEqual(Move.favorite.decision, .keep)
        XCTAssertEqual(Move.delete.decision, .delete)
        XCTAssertNil(Move.later.decision)
    }
}
