import XCTest
@testable import PRTGBar

@MainActor
final class DemoDataTests: XCTestCase {

    func testDemoDataCoversMenuCases() {
        let model = MenuModel.make(
            roots: DemoData.buildTree(), timestamps: DemoData.problemTimestamps, sort: .newestFirst,
            serverURL: DemoData.serverURL, lastUpdated: nil, error: nil, snoozedUntil: nil
        )

        XCTAssertGreaterThanOrEqual(model.summary.down, 1)
        XCTAssertGreaterThanOrEqual(model.summary.warning, 1)
        XCTAssertGreaterThanOrEqual(model.problems.acknowledged.count, 1)
        XCTAssertGreaterThanOrEqual(model.problems.paused.count, 1)
        XCTAssertTrue(model.projects.flatMap(\.devices).contains { !$0.path.isEmpty })
        XCTAssertTrue(model.projects.contains { $0.displayName.contains(" · ") })
    }

    func testDemoHistoryShowsEarlierOutage() {
        let history = StatusHistory(fileURL: nil)
        DemoData.seedHistory(history, now: Date())

        let summary = history.summary(for: 101, now: Date())

        XCTAssertGreaterThanOrEqual(summary.outageCount, 1)
        XCTAssertNotNil(summary.upRatio)
    }
}
