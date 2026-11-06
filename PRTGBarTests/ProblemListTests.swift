import XCTest
@testable import PRTGBar

final class ProblemListTests: XCTestCase {

    // MARK: - Helpers

    private func sensor(_ id: Int, _ status: SensorStatus, name: String? = nil, message: String? = nil, lastDown: Date? = nil) -> TreeNode {
        TreeNode(id: id, name: name ?? "Sensor \(id)", kind: .sensor, status: status, message: message, lastDown: lastDown)
    }

    private func tree(_ devices: [TreeNode]) -> [TreeNode] {
        [TreeNode(id: 1, name: "Dresden", kind: .probedevice, status: .up, children: [
            TreeNode(id: 10, name: "Kunde A", kind: .group, status: .up, children: devices)
        ])]
    }

    private func device(_ id: Int, _ name: String, _ sensors: [TreeNode]) -> TreeNode {
        TreeNode(id: id, name: name, kind: .device, status: .up, children: sensors)
    }

    private func make(_ roots: [TreeNode], sort: ProblemSort = .newestFirst) -> ProblemList {
        ProblemList.make(from: roots, timestamps: [:], sort: sort)
    }

    // MARK: - Tests

    func testSplitsDownWarningAcknowledged() {
        let roots = tree([device(100, "web", [
            sensor(1, .down), sensor(2, .partialdown), sensor(3, .warning), sensor(4, .unusual),
            sensor(5, .down, message: "Acknowledged by admin: maintenance"), sensor(6, .up)
        ])])

        let list = make(roots)

        XCTAssertEqual(Set(list.down.map(\.id)), [1, 2])
        XCTAssertEqual(Set(list.warning.map(\.id)), [3, 4])
        XCTAssertEqual(list.acknowledged.map(\.id), [5])
        XCTAssertEqual(list.down.first?.projectName, "Kunde A")
        XCTAssertEqual(list.down.first?.deviceId, 100)
    }

    func testNewestFirstSort() {
        let roots = tree([device(100, "web", [
            sensor(1, .down, lastDown: Date(timeIntervalSince1970: 100)),
            sensor(2, .down, lastDown: Date(timeIntervalSince1970: 300)),
            sensor(3, .down, name: "B"),
            sensor(4, .down, name: "A"),
            sensor(5, .down, lastDown: Date(timeIntervalSince1970: 200))
        ])])

        XCTAssertEqual(make(roots, sort: .newestFirst).down.map(\.id), [2, 5, 1, 4, 3])
    }

    func testLongestFirstSort() {
        let roots = tree([device(100, "web", [
            sensor(1, .down, lastDown: Date(timeIntervalSince1970: 100)),
            sensor(2, .down, lastDown: Date(timeIntervalSince1970: 300)),
            sensor(3, .down, name: "B"),
            sensor(4, .down, name: "A")
        ])])

        XCTAssertEqual(make(roots, sort: .longestFirst).down.map(\.id), [1, 2, 4, 3])
    }

    func testByDeviceSort() {
        let roots = tree([
            device(100, "zeta", [sensor(1, .down, name: "b"), sensor(2, .down, name: "a")]),
            device(101, "alpha", [sensor(3, .down, name: "z")])
        ])

        XCTAssertEqual(make(roots, sort: .byDevice).down.map(\.id), [3, 2, 1])
    }

    func testPausedGroupedPerDevice() {
        let paused = (1...12).map { sensor($0, .paused) }
        let roots = tree([device(100, "web", paused + [sensor(99, .up)])])

        let list = make(roots)

        XCTAssertEqual(list.paused, [PausedDeviceLine(deviceId: 100, heading: "web", pausedCount: 12)])
        XCTAssertTrue(list.down.isEmpty)
        XCTAssertTrue(list.acknowledged.isEmpty)
    }

    func testAcknowledgedAndPausedCappedAt50() {
        let acknowledged = (1...40).map { sensor($0, .down, message: "Acknowledged by admin: x") }
        let pausedDevices = (1...20).map { device(200 + $0, "dev\($0)", [sensor(1000 + $0, .paused)]) }
        let roots = tree([device(100, "web", acknowledged)] + pausedDevices)

        let capped = make(roots).cappedEntries(limit: 50)

        XCTAssertEqual(capped.entries.count, 50)
        XCTAssertEqual(capped.remaining, 10)
        guard case .sensor = capped.entries[0] else { return XCTFail("acknowledged sensors come first") }
        guard case .pausedDevice = capped.entries[49] else { return XCTFail("paused lines follow") }
    }
}
