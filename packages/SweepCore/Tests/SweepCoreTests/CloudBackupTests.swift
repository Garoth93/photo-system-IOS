import Foundation
import XCTest
@testable import SweepCore

/// Synthetic data only (identifiers like "TEST-…"), never real backups.
final class CloudBackupTests: XCTestCase {
    private func sampleState() -> SweepState {
        var st = SweepState(deletedCount: 4, freedBytes: 12_000_000)
        st.apply(.keep, to: "TEST-L1")
        st.apply(.keep, to: "TEST-L2")
        st.apply(.delete, to: "TEST-L3")
        st.apply(.delete, to: "TEST-L4")
        return st
    }

    func testRoundTripAndHeader() throws {
        let file = BackupFile(state: sampleState(),
                              settings: SweepSettings(filter: .videos, order: .random, cloudBackup: false),
                              albums: [AlbumSummary(title: "Album TEST", kind: "album", total: 10, reviewed: 3)],
                              cloudIDs: ["TEST-L1": "TEST-C1", "TEST-L3": "TEST-C3"],
                              now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(file.version, BackupFile.currentVersion)
        XCTAssertEqual(file.app, "Sweep")
        XCTAssertEqual(file.kept, [PhotoRef(local: "TEST-L1", cloud: "TEST-C1"), PhotoRef(local: "TEST-L2")])
        XCTAssertEqual(file.trash, [PhotoRef(local: "TEST-L3", cloud: "TEST-C3"), PhotoRef(local: "TEST-L4")])
        XCTAssertEqual(file.cloudIDs.sorted(), ["TEST-C1", "TEST-C3"])
        XCTAssertFalse(file.isEmpty)

        let data = try file.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""version":1"#))
        XCTAssertEqual(try BackupFile.decode(data), file)
    }

    func testDecodeErrors() {
        XCTAssertThrowsError(try BackupFile.decode(Data("nope".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        XCTAssertThrowsError(try BackupFile.decode(Data(#"{"app":"Cresta","version":1}"#.utf8))) { XCTAssertEqual($0 as? BackupError, .wrongApp) }
        XCTAssertThrowsError(try BackupFile.decode(Data(#"{"app":"Sweep","version":99}"#.utf8))) { XCTAssertEqual($0 as? BackupError, .tooNew) }
    }

    func testTolerantDecoding() throws {
        let minimal = Data(#"{"app":"Sweep","version":1,"kept":[{"local":"TEST-A"}],"settings":{"order":"oldestFirst","filter":"???"}}"#.utf8)
        let file = try BackupFile.decode(minimal)
        XCTAssertEqual(file.kept, [PhotoRef(local: "TEST-A")])
        XCTAssertEqual(file.trash, [])
        XCTAssertEqual(file.settings, SweepSettings(filter: .all, order: .oldestFirst, cloudBackup: true))
    }

    func testEmptyStateIsEmptyBackup() {
        XCTAssertTrue(BackupFile(state: SweepState(), settings: SweepSettings()).isEmpty)
        XCTAssertFalse(BackupFile(state: SweepState(deletedCount: 1), settings: SweepSettings()).isEmpty)
    }

    func testRestoreMapsCloudIdentifiersOnANewPhone() {
        let file = BackupFile(state: sampleState(), settings: SweepSettings(),
                              cloudIDs: ["TEST-L1": "TEST-C1", "TEST-L3": "TEST-C3", "TEST-L4": "TEST-C4"])
        // New phone: none of the old local ids exist; C1 and C3 are in iCloud Photos.
        let result = file.restoredState(existing: ["TEST-N1", "TEST-N3", "TEST-X"],
                                        cloudToLocal: ["TEST-C1": "TEST-N1", "TEST-C3": "TEST-N3"])
        XCTAssertEqual(result.state.kept, ["TEST-N1"])
        XCTAssertEqual(result.state.trash, ["TEST-N3"])
        XCTAssertEqual(result.missing, 2)   // L2 (no cloud id) and L4 (not in the library)
        XCTAssertEqual(result.state.deletedCount, 4)
        XCTAssertEqual(result.state.freedBytes, 12_000_000)

        // Same phone: local ids win, nothing missing.
        let same = file.restoredState(existing: ["TEST-L1", "TEST-L2", "TEST-L3", "TEST-L4"], cloudToLocal: [:])
        XCTAssertEqual(same.state, sampleState())
        XCTAssertEqual(same.missing, 0)
    }

    func testFileNamesAndPruning() {
        let day = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current,
                                 year: 2026, month: 3, day: 7, hour: 12).date!
        XCTAssertEqual(CloudBackupPlan.dailyName(for: day), "Sweep-backup-2026-03-07.json")
        XCTAssertEqual(CloudBackupPlan.realName(".Sweep-backup-latest.json.icloud"), "Sweep-backup-latest.json")

        var names = ["Sweep-backup-latest.json", "other.txt", "Cresta-backup-2026-01-01.json"]
        let calendar = Calendar(identifier: .gregorian)
        let jan1 = DateComponents(calendar: calendar, timeZone: .current, year: 2026, month: 1, day: 1, hour: 12).date!
        for offset in 0..<35 {   // 1 January … 4 February
            names.append(CloudBackupPlan.dailyName(for: calendar.date(byAdding: .day, value: offset, to: jan1)!))
        }
        let entries = CloudBackupPlan.entries(fromFileNames: names)
        XCTAssertTrue(entries.first?.isLatest == true)
        XCTAssertEqual(entries.count, 1 + 35)
        XCTAssertEqual(entries[1].name, "Sweep-backup-2026-02-04.json")
        let prune = CloudBackupPlan.namesToPrune(names)
        XCTAssertEqual(prune.count, 5)
        XCTAssertTrue(prune.contains("Sweep-backup-2026-01-01.json"))
        XCTAssertFalse(prune.contains("Sweep-backup-latest.json"))
    }

    func testFingerprintIgnoresTimestamp() {
        let a = BackupFile(state: sampleState(), settings: SweepSettings(), now: Date(timeIntervalSince1970: 1))
        let b = BackupFile(state: sampleState(), settings: SweepSettings(), now: Date(timeIntervalSince1970: 999))
        XCTAssertEqual(CloudBackupPlan.fingerprint(a), CloudBackupPlan.fingerprint(b))
        var st = sampleState()
        st.apply(.keep, to: "TEST-L9")
        let c = BackupFile(state: st, settings: SweepSettings())
        XCTAssertNotEqual(CloudBackupPlan.fingerprint(a), CloudBackupPlan.fingerprint(c))
    }
}
