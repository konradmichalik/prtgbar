import XCTest
@testable import PRTGBar

final class StatusItemStateTests: XCTestCase {

    func testAllUp() {
        let model = makeModel(roots: [device(statuses: [.up, .up])])
        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: true), .allUp)
    }

    func testWarningsOnlyWhenIndicatorEnabled() {
        let model = makeModel(roots: [device(statuses: [.up, .warning, .unusual])])

        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: true), .warningsOnly(2),
                       "unusual counts towards the warning indicator")
        XCTAssertEqual(StatusItemState.make(model: model, showCount: false, showWarningIndicator: true), .warningsOnly(0))
        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: false), .allUp)
    }

    func testDownCountsUnacknowledgedOnly() {
        let sensors = [
            TreeNode(id: 1, name: "a", kind: .sensor, status: .down),
            TreeNode(id: 2, name: "b", kind: .sensor, status: .partialdown),
            TreeNode(id: 3, name: "c", kind: .sensor, status: .down, message: "Acknowledged by admin: ok"),
            TreeNode(id: 4, name: "d", kind: .sensor, status: .warning),
        ]
        let model = makeModel(roots: [TreeNode(id: 10, name: "dev", kind: .device, status: .down, children: sensors)])

        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: true), .down(2))
        XCTAssertEqual(StatusItemState.make(model: model, showCount: false, showWarningIndicator: false), .down(0))
    }

    func testUnreachableWinsOverEverything() {
        let model = makeModel(roots: [device(statuses: [.down])], error: "Network error",
                              snoozedUntil: Date().addingTimeInterval(600))
        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: true), .unreachable)
    }

    func testWriteErrorWithDownSensorsStaysDown() {
        let model = makeModel(roots: [device(statuses: [.down, .up])],
                              actionError: "This API key is read-only or lacks permission for this action.")
        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: false), .down(1))
    }

    func testSnoozedKeepsDownCount() {
        let model = makeModel(roots: [device(statuses: [.down, .up])], snoozedUntil: Date().addingTimeInterval(600))

        XCTAssertEqual(StatusItemState.make(model: model, showCount: true, showWarningIndicator: false),
                       .snoozed(downCount: 1))
        XCTAssertEqual(StatusItemState.make(model: model, showCount: false, showWarningIndicator: false),
                       .snoozed(downCount: 0))
    }

    func testCountText() {
        XCTAssertEqual(StatusItemState.allUp.countText, "")
        XCTAssertEqual(StatusItemState.down(3).countText, "3")
        XCTAssertEqual(StatusItemState.down(0).countText, "")
        XCTAssertEqual(StatusItemState.warningsOnly(4).countText, "4")
        XCTAssertEqual(StatusItemState.snoozed(downCount: 2).countText, "2")
        XCTAssertEqual(StatusItemState.unreachable.countText, "")
    }

    func testOnlySnoozeKeepsABadge() {
        XCTAssertEqual(StatusItemState.snoozed(downCount: 1).badgeSymbol, "bell.slash")
        for state in [StatusItemState.allUp, .warningsOnly(0), .warningsOnly(3), .down(0), .down(2), .unreachable] {
            XCTAssertNil(state.badgeSymbol, "\(state): the gauge itself shows the state")
        }
    }

    func testGaugeLevelFollowsTheWorstState() {
        XCTAssertEqual(StatusItemState.allUp.gaugeLevel, .ok)
        XCTAssertEqual(StatusItemState.unreachable.gaugeLevel, .ok)
        XCTAssertEqual(StatusItemState.warningsOnly(0).gaugeLevel, .warning)
        XCTAssertEqual(StatusItemState.down(0).gaugeLevel, .down, "a hidden count still turns the gauge to down")
        XCTAssertEqual(StatusItemState.snoozed(downCount: 2).gaugeLevel, .down)
        XCTAssertEqual(StatusItemState.snoozed(downCount: 0).gaugeLevel, .ok)
    }

    func testSummaryGaugeLevel() {
        XCTAssertEqual(GaugeLevel(StatusSummary(up: 3, down: 0, warning: 0, paused: 0, unknown: 0)), .ok)
        XCTAssertEqual(GaugeLevel(StatusSummary(up: 3, down: 0, warning: 1, paused: 0, unknown: 0)), .warning)
        XCTAssertEqual(GaugeLevel(StatusSummary(up: 3, down: 1, warning: 1, paused: 0, unknown: 0)), .down)
        XCTAssertEqual(GaugeLevel(StatusSummary(up: 3, down: 0, warning: 0, paused: 0, unknown: 0, unusual: 1)), .warning)
    }

    // MARK: - Helpers

    private func device(statuses: [SensorStatus]) -> TreeNode {
        let sensors = statuses.enumerated().map { index, status in
            TreeNode(id: index + 1, name: "s\(index)", kind: .sensor, status: status)
        }
        return TreeNode(id: 100, name: "dev", kind: .device, status: .up, children: sensors)
    }

    private func makeModel(
        roots: [TreeNode], error: String? = nil, actionError: String? = nil, snoozedUntil: Date? = nil
    ) -> MenuModel {
        MenuModel.make(MenuModel.Input(
            roots: roots, serverURL: "prtg.example.com", lastUpdated: Date(),
            error: error, actionError: actionError, snoozedUntil: snoozedUntil
        ))
    }
}
