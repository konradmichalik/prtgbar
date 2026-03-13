import XCTest
@testable import PRTGBar

final class TreeFilterTests: XCTestCase {

    private func makeTree() -> [TreeNode] {
        let sensor1 = TreeNode(id: 1000, name: "Ping", kind: .sensor, status: .up, message: "24 ms")
        let sensor2 = TreeNode(id: 1001, name: "HTTP", kind: .sensor, status: .warning, message: "Timeout")
        let sensor3 = TreeNode(id: 1002, name: "CPU Load", kind: .sensor, status: .down, message: "99%")
        let device = TreeNode(id: 100, name: "Webserver", kind: .device, status: .up, children: [sensor1, sensor2])
        let device2 = TreeNode(id: 101, name: "Database", kind: .device, status: .down, children: [sensor3])
        let group = TreeNode(id: 10, name: "Production", kind: .group, status: .up, children: [device, device2])
        let probe = TreeNode(id: 1, name: "Local Probe", kind: .probedevice, status: .up, children: [group])
        return [probe]
    }

    func testEmptyQueryReturnsAllNodes() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, 1)
        XCTAssertTrue(result[0] === tree[0], "Should return same nodes when query is empty")
    }

    func testMatchingLeafPreservesAncestors() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "ping")

        XCTAssertEqual(result.count, 1, "Probe should be preserved")
        XCTAssertEqual(result[0].name, "Local Probe")

        let group = result[0].children
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(group[0].name, "Production")

        let devices = group[0].children
        XCTAssertEqual(devices.count, 1, "Only Webserver should remain")
        XCTAssertEqual(devices[0].name, "Webserver")

        let sensors = devices[0].children
        XCTAssertEqual(sensors.count, 1)
        XCTAssertEqual(sensors[0].name, "Ping")
    }

    func testNoMatchReturnsEmpty() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "nonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    func testMatchingContainerIncludesAllChildren() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "webserver")

        XCTAssertEqual(result.count, 1)
        let group = result[0].children[0]
        let device = group.children[0]
        XCTAssertEqual(device.name, "Webserver")
        XCTAssertEqual(device.children.count, 2, "All children of matched container should be included")
    }

    func testCaseInsensitiveMatching() {
        let tree = makeTree()
        let upper = TreeFilter.filter(tree, query: "PING")
        let lower = TreeFilter.filter(tree, query: "ping")
        let mixed = TreeFilter.filter(tree, query: "PiNg")

        XCTAssertEqual(upper.count, 1)
        XCTAssertEqual(lower.count, 1)
        XCTAssertEqual(mixed.count, 1)
    }

    func testMessageMatching() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "timeout")

        XCTAssertEqual(result.count, 1)
        let sensors = result[0].children[0].children[0].children
        XCTAssertEqual(sensors.count, 1, "Only the sensor with matching message should be included")
        XCTAssertEqual(sensors[0].name, "HTTP")
    }

    func testMultipleMatchesAcrossDevices() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "a")

        XCTAssertEqual(result.count, 1)
        let group = result[0].children[0]
        XCTAssertEqual(group.children.count, 2, "Both devices should match (Database, Webserver contains sensors with 'a')")
    }

    func testEmptyTreeReturnsEmpty() {
        let result = TreeFilter.filter([], query: "anything")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Status Filter

    func testStatusFilterUp() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "", statusFilter: .up)

        XCTAssertEqual(result.count, 1)
        let sensors = collectSensors(result)
        XCTAssertTrue(sensors.allSatisfy { $0.status == .up })
        XCTAssertEqual(sensors.count, 1, "Only Ping is up")
    }

    func testStatusFilterDown() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "", statusFilter: .down)

        let sensors = collectSensors(result)
        XCTAssertTrue(sensors.allSatisfy { $0.status == .down || $0.status == .partialdown })
        XCTAssertEqual(sensors.count, 1, "Only CPU Load is down")
    }

    func testStatusFilterWarning() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "", statusFilter: .warning)

        let sensors = collectSensors(result)
        XCTAssertTrue(sensors.allSatisfy { $0.status == .warning || $0.status == .unusual })
        XCTAssertEqual(sensors.count, 1, "Only HTTP is warning")
    }

    func testStatusFilterNoMatch() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "", statusFilter: .paused)
        XCTAssertTrue(result.isEmpty, "No paused sensors in tree")
    }

    func testStatusFilterCombinedWithQuery() {
        let tree = makeTree()
        let result = TreeFilter.filter(tree, query: "webserver", statusFilter: .up)

        XCTAssertEqual(result.count, 1)
        let sensors = collectSensors(result)
        XCTAssertEqual(sensors.count, 1)
        XCTAssertEqual(sensors[0].name, "Ping")
    }

    // MARK: - Helpers

    private func collectSensors(_ nodes: [TreeNode]) -> [TreeNode] {
        var sensors: [TreeNode] = []
        for node in nodes {
            if node.kind == .sensor {
                sensors.append(node)
            }
            sensors.append(contentsOf: collectSensors(node.children))
        }
        return sensors
    }
}
