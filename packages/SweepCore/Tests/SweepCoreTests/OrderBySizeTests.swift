import Foundation
import XCTest
@testable import SweepCore

/// Synthetic data only (identifiers like "TEST-…").
final class OrderBySizeTests: XCTestCase {
    func testLargestFirstIsStableForEqualOrUnknownSizes() {
        let ids = ["TEST-1", "TEST-2", "TEST-3", "TEST-4"]
        let sizes: [String: Int64] = ["TEST-2": 5_000, "TEST-3": 9_000, "TEST-4": 5_000]
        XCTAssertEqual(SweepOrder.largestFirst.arrange(newestFirst: ids, sizes: sizes),
                       ["TEST-3", "TEST-2", "TEST-4", "TEST-1"])
        XCTAssertTrue(SweepOrder.largestFirst.needsSizes)
        XCTAssertFalse(SweepOrder.newestFirst.needsSizes)
        XCTAssertEqual(SweepOrder.allCases.count, 4)
    }
}
