import XCTest
@testable import PRTGBar

final class TreeBuildingTests: XCTestCase {

    func testBuildTreeFromFlatList() {
        let objects = [
            PrtgObject(
                id: 1, name: "Hosted Probe", kind: .probedevice,
                status: .up, message: nil, parent: nil,
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 10, name: "Team A-Team", kind: .group,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Hosted Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 100, name: "Webserver", kind: .device,
                status: .up, message: nil,
                parent: ParentRef(id: 10, type: "group", name: "Team A-Team"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 1000, name: "Ping", kind: .sensor,
                status: .up, message: "24 ms",
                parent: ParentRef(id: 100, type: "device", name: "Webserver"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 1001, name: "HTTP", kind: .sensor,
                status: .warning, message: "1,379 ms",
                parent: ParentRef(id: 100, type: "device", name: "Webserver"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
        ]

        let tree = TreeBuilder.buildTree(from: objects)

        XCTAssertEqual(tree.count, 1, "Should have one root (probe)")
        XCTAssertEqual(tree[0].name, "Hosted Probe")
        XCTAssertEqual(tree[0].kind, .probedevice)

        XCTAssertEqual(tree[0].children.count, 1, "Probe should have one group")
        let group = tree[0].children[0]
        XCTAssertEqual(group.name, "Team A-Team")
        XCTAssertEqual(group.kind, .group)

        XCTAssertEqual(group.children.count, 1, "Group should have one device")
        let device = group.children[0]
        XCTAssertEqual(device.name, "Webserver")
        XCTAssertEqual(device.kind, .device)

        XCTAssertEqual(device.children.count, 2, "Device should have two sensors")
    }

    func testWorstStatusPropagation() {
        let objects = [
            PrtgObject(
                id: 1, name: "Probe", kind: .probedevice,
                status: .up, message: nil, parent: nil,
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 10, name: "Device", kind: .device,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 100, name: "Ping", kind: .sensor,
                status: .up, message: nil,
                parent: ParentRef(id: 10, type: "device", name: "Device"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 101, name: "HTTP", kind: .sensor,
                status: .down, message: nil,
                parent: ParentRef(id: 10, type: "device", name: "Device"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
        ]

        let tree = TreeBuilder.buildTree(from: objects)

        XCTAssertEqual(tree[0].worstStatus, .down, "Probe should reflect worst child status")
        XCTAssertEqual(tree[0].children[0].worstStatus, .down, "Device should reflect worst sensor status")
        XCTAssertTrue(tree[0].hasDownSensors)
    }

    func testEmptyList() {
        let tree = TreeBuilder.buildTree(from: [])
        XCTAssertTrue(tree.isEmpty)
    }

    func testTotalSensorCount() {
        let objects = [
            PrtgObject(
                id: 1, name: "Probe", kind: .probedevice,
                status: .up, message: nil, parent: nil,
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 10, name: "Sensor A", kind: .sensor,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 11, name: "Sensor B", kind: .sensor,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
        ]

        let tree = TreeBuilder.buildTree(from: objects)
        XCTAssertEqual(tree[0].totalSensorCount, 2)
    }

    func testSortingByKindAndName() {
        let objects = [
            PrtgObject(
                id: 1, name: "Probe", kind: .probedevice,
                status: .up, message: nil, parent: nil,
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 10, name: "Zebra Sensor", kind: .sensor,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 11, name: "Alpha Group", kind: .group,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
            PrtgObject(
                id: 12, name: "Alpha Device", kind: .device,
                status: .up, message: nil,
                parent: ParentRef(id: 1, type: "probedevice", name: "Probe"),
                tags: nil, active: true, sensorStatusSummary: nil
            ),
        ]

        let tree = TreeBuilder.buildTree(from: objects)
        let children = tree[0].children

        // Groups before devices before sensors
        XCTAssertEqual(children[0].kind, .group)
        XCTAssertEqual(children[1].kind, .device)
        XCTAssertEqual(children[2].kind, .sensor)
    }
}
