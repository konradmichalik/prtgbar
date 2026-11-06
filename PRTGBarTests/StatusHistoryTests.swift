import XCTest
@testable import PRTGBar

@MainActor
final class StatusHistoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let slot: TimeInterval = 1800

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    func testSegmentsCover24Hours() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .up], at: now)
        let summary = history.summary(for: 1, now: now)
        XCTAssertEqual(summary.segments.count, 48)
        XCTAssertEqual(summary.segments.last, .up)
        XCTAssertEqual(summary.segments.first, .noData)
    }

    func testGapIsNoDataAndExcludedFromRatio() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .up], at: ago(3 * slot - 10))
        history.record([1: .down], at: ago(10))
        let summary = history.summary(for: 1, now: now)
        XCTAssertEqual(summary.segments[45], .up)
        XCTAssertEqual(summary.segments[46], .noData)
        XCTAssertEqual(summary.segments[47], .down)
        XCTAssertEqual(summary.upRatio, 0.5)
    }

    func testNoPollsGivesNilRatio() {
        let history = StatusHistory(fileURL: nil)
        let summary = history.summary(for: 99, now: now)
        XCTAssertNil(summary.upRatio)
        XCTAssertEqual(summary.outageCount, 0)
    }

    func testOutageCountsRuns() {
        let history = StatusHistory(fileURL: nil)
        // Segments 40, 41 down, 42 up, 44 partialdown, 45 up
        history.record([1: .down], at: ago(7.5 * slot))
        history.record([1: .down], at: ago(6.5 * slot))
        history.record([1: .up], at: ago(5.5 * slot))
        history.record([1: .partialdown], at: ago(3.5 * slot))
        history.record([1: .up], at: ago(2.5 * slot))
        let summary = history.summary(for: 1, now: now)
        XCTAssertEqual(summary.segments[40], .down)
        XCTAssertEqual(summary.segments[41], .down)
        XCTAssertEqual(summary.segments[42], .up)
        XCTAssertEqual(summary.segments[44], .down)
        XCTAssertEqual(summary.outageCount, 2)
    }

    func testDownWinsWithinSegment() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .down], at: ago(100))
        history.record([1: .up], at: ago(50))
        XCTAssertEqual(history.summary(for: 1, now: now).segments[47], .down)
    }

    func testNonDownStatusesCountAsUp() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .warning], at: ago(100))
        XCTAssertEqual(history.summary(for: 1, now: now).segments[47], .up)
    }

    func testRecordPrunesOlderThan24h() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .down], at: ago(25 * 3600))
        history.record([1: .up], at: now)
        XCTAssertEqual(history.slotCount(for: 1), 1)
        XCTAssertEqual(history.summary(for: 1, now: now).upRatio, 1.0)
    }

    func testPruneBoundaryKeepsExactly24h() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .down], at: ago(24 * 3600))
        history.record([2: .down], at: ago(24 * 3600 + 1))
        history.record([:], at: now)
        XCTAssertEqual(history.slotCount(for: 1), 1)
        XCTAssertEqual(history.slotCount(for: 2), 0)
    }

    func testStorageIsBoundedPerSensor() {
        let history = StatusHistory(fileURL: nil)
        for poll in 0..<200 {
            history.record([1: poll % 7 == 0 ? .down : .up], at: ago(Double(199 - poll) * 60))
        }
        XCTAssertLessThanOrEqual(history.slotCount(for: 1), 48)
        XCTAssertEqual(history.slotCount(for: 1), 8)
    }

    func testSaveIsDueOncePerSlot() {
        let history = StatusHistory(fileURL: nil)
        history.record([1: .up], at: ago(100))
        XCTAssertTrue(history.saveIfNeeded(now: ago(100)))
        XCTAssertFalse(history.saveIfNeeded(now: ago(50)))
        XCTAssertTrue(history.saveIfNeeded(now: now.addingTimeInterval(10)))
    }

    func testLoadPrunesOlderThan24h() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let old = Int(now.timeIntervalSince1970 - 25 * 3600)
        let recent = Int(now.timeIntervalSince1970 - slot)
        try Data(#"{"1":{"\#(old)":2,"\#(recent)":1}}"#.utf8).write(to: file)
        let history = StatusHistory(fileURL: file)
        try history.load(now: now)
        XCTAssertEqual(history.slotCount(for: 1), 1)
        XCTAssertEqual(history.summary(for: 1, now: now).segments[47], .up)
    }

    func testLoadMergesDuplicateSensorKeys() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let newer = Int(now.timeIntervalSince1970 - slot)
        let older = Int(now.timeIntervalSince1970 - 2 * slot)
        try Data(#"{"1":{"\#(newer)":2},"01":{"\#(older)":1}}"#.utf8).write(to: file)
        let history = StatusHistory(fileURL: file)
        try history.load(now: now)
        XCTAssertEqual(history.slotCount(for: 1), 2)
        XCTAssertEqual(history.summary(for: 1, now: now).segments[47], .down)
        XCTAssertEqual(history.summary(for: 1, now: now).segments[46], .up)
    }

    func testRoundTripSaveLoad() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")

        let first = StatusHistory(fileURL: file)
        first.record([1: .down, 2: .up], at: ago(100))
        try first.save()

        let second = StatusHistory(fileURL: file)
        try second.load(now: now)
        XCTAssertEqual(second.summary(for: 1, now: now), first.summary(for: 1, now: now))
        XCTAssertEqual(second.summary(for: 2, now: now).segments[47], .up)
    }

    func testLoadMissingFileLeavesHistoryEmpty() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        let history = StatusHistory(fileURL: file)
        try history.load(now: now)
        XCTAssertNil(history.summary(for: 1, now: now).upRatio)
    }

    func testLoadCorruptFileThrows() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        XCTAssertThrowsError(try StatusHistory(fileURL: file).load())
    }
}
