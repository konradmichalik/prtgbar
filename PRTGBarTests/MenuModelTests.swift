import XCTest
@testable import PRTGBar

final class MenuModelTests: XCTestCase {

    func testTruncatedKeepsShortStrings() {
        XCTAssertEqual(MenuText.truncated("web-01"), "web-01")
        XCTAssertEqual(MenuText.truncated(String(repeating: "a", count: 48)).count, 48)
    }

    func testTruncatedMiddleEllipsis() {
        let name = String(repeating: "a", count: 30) + String(repeating: "b", count: 30)
        let result = MenuText.truncated(name)

        XCTAssertEqual(result.count, 48)
        XCTAssertEqual(result, String(repeating: "a", count: 24) + "…" + String(repeating: "b", count: 23))
    }

    func testUpdatedAgoCopy() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(MenuText.updatedAgo(now.addingTimeInterval(-3), now: now), "Updated just now")
        XCTAssertEqual(MenuText.updatedAgo(now.addingTimeInterval(-30), now: now), "Updated 30 s ago")
        XCTAssertEqual(MenuText.updatedAgo(now.addingTimeInterval(-300), now: now), "Updated 5 min ago")
        XCTAssertEqual(MenuText.updatedAgo(now.addingTimeInterval(-7200), now: now), "Updated 2 h ago")
    }

    func testSummaryLineOmitsZeroCounts() {
        let full = StatusSummary(up: 1240, down: 2, warning: 3, paused: 4, unknown: 0)
        XCTAssertEqual(MenuText.summaryLine(full), "2 Down · 3 Warning · 1,240 Up")

        let quiet = StatusSummary(up: 7, down: 0, warning: 0, paused: 0, unknown: 0)
        XCTAssertEqual(MenuText.summaryLine(quiet), "7 Up")
    }

    func testHostFromServerURL() {
        XCTAssertEqual(makeModel(serverURL: "https://prtg.example.com:8443/", roots: []).serverHost, "prtg.example.com")
        XCTAssertEqual(makeModel(serverURL: "prtg.example.com", roots: []).serverHost, "prtg.example.com")
        XCTAssertFalse(makeModel(serverURL: "", roots: []).isConfigured)
    }

    func testConfiguredNeedsServerAndKey() {
        XCTAssertFalse(MenuModel.make(MenuModel.Input(serverURL: "prtg.example.com", hasAPIKey: false)).isConfigured)
        XCTAssertFalse(MenuModel.make(MenuModel.Input(serverURL: "", hasAPIKey: true)).isConfigured)
        XCTAssertTrue(MenuModel.make(MenuModel.Input(serverURL: "prtg.example.com", hasAPIKey: true)).isConfigured)
    }

    func testSummaryCountsUnacknowledgedSensorsOnly() {
        let sensors = [
            TreeNode(id: 1, name: "a", kind: .sensor, status: .up),
            TreeNode(id: 2, name: "b", kind: .sensor, status: .down),
            TreeNode(id: 3, name: "c", kind: .sensor, status: .down, message: "Acknowledged by admin: ok"),
            TreeNode(id: 4, name: "d", kind: .sensor, status: .unusual),
            TreeNode(id: 5, name: "e", kind: .sensor, status: .paused),
        ]
        let device = TreeNode(id: 10, name: "dev", kind: .device, status: .up, children: sensors)

        let summary = makeModel(serverURL: "x", roots: [device]).summary

        XCTAssertEqual(summary, StatusSummary(up: 1, down: 1, warning: 1, paused: 1, unknown: 0))
    }

    func testMakeIsFastFor5000Sensors() {
        var probeChildren: [TreeNode] = []
        for p in 0..<60 {
            var devices: [TreeNode] = []
            for d in 0..<10 {
                let sensors = (0..<8).map { s in
                    let id = 100_000 + p * 1000 + d * 10 + s
                    return TreeNode(id: id, name: "S\(id)", kind: .sensor, status: id % 50 == 0 ? .down : .up)
                }
                devices.append(TreeNode(id: 10_000 + p * 100 + d, name: "dev-\(p)-\(d)", kind: .device,
                                        status: .up, children: sensors))
            }
            probeChildren.append(TreeNode(id: 1000 + p, name: "Project \(p)", kind: .group, status: .up, children: devices))
        }
        let roots = [TreeNode(id: 1, name: "Probe", kind: .probedevice, status: .up, children: probeChildren)]

        let start = Date()
        let model = makeModel(serverURL: "prtg.example.com", roots: roots)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(model.projects.count, 60)
        XCTAssertLessThan(elapsed, 0.1)
    }

    // MARK: - Helpers

    private func makeModel(serverURL: String, roots: [TreeNode]) -> MenuModel {
        MenuModel.make(MenuModel.Input(roots: roots, serverURL: serverURL))
    }
}
