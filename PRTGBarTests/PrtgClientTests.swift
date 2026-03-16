import XCTest
@testable import PRTGBar

final class PrtgClientTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodePrtgObject() throws {
        let json = """
        {
            "id": 3074,
            "name": "Ping",
            "kind": "sensor",
            "status": "up",
            "message": "24 ms",
            "parent": {
                "id": 1001,
                "type": "device",
                "name": "Server-01"
            },
            "tags": ["ping", "network"],
            "active": true
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder().decode(PrtgObject.self, from: json)

        XCTAssertEqual(object.id, 3074)
        XCTAssertEqual(object.name, "Ping")
        XCTAssertEqual(object.kind, .sensor)
        XCTAssertEqual(object.status, .up)
        XCTAssertEqual(object.message, "24 ms")
        XCTAssertEqual(object.parent?.id, 1001)
        XCTAssertEqual(object.parent?.name, "Server-01")
        XCTAssertEqual(object.tags, ["ping", "network"])
        XCTAssertEqual(object.active, true)
    }

    func testDecodeObjectWithStatusSummary() throws {
        let json = """
        {
            "id": 1001,
            "name": "Server-01",
            "kind": "device",
            "status": "up",
            "parent": {
                "id": 10,
                "type": "group",
                "name": "Servers"
            },
            "sensor_status_summary": {
                "up": 12,
                "down": 1,
                "warning": 2,
                "paused": 3,
                "unknown": 0
            }
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder().decode(PrtgObject.self, from: json)

        XCTAssertNotNil(object.sensorStatusSummary)
        XCTAssertEqual(object.sensorStatusSummary?.up, 12)
        XCTAssertEqual(object.sensorStatusSummary?.down, 1)
        XCTAssertEqual(object.sensorStatusSummary?.warning, 2)
        XCTAssertEqual(object.sensorStatusSummary?.paused, 3)
        XCTAssertEqual(object.sensorStatusSummary?.unknown, 0)
        XCTAssertEqual(object.sensorStatusSummary?.total, 18)
    }

    func testDecodeSensorStatus() throws {
        let statuses: [(String, SensorStatus)] = [
            ("\"up\"", .up),
            ("\"down\"", .down),
            ("\"warning\"", .warning),
            ("\"paused\"", .paused),
            ("\"unusual\"", .unusual),
            ("\"partialdown\"", .partialdown),
            ("\"unknown\"", .unknown),
        ]

        for (json, expected) in statuses {
            let decoded = try JSONDecoder().decode(SensorStatus.self, from: json.data(using: .utf8)!)
            XCTAssertEqual(decoded, expected, "Failed for \(json)")
        }
    }

    func testDecodeObjectsResponse() throws {
        let json = """
        {
            "items": [
                {
                    "id": 1,
                    "name": "Probe",
                    "kind": "probedevice",
                    "status": "up"
                },
                {
                    "id": 2,
                    "name": "Ping",
                    "kind": "sensor",
                    "status": "down",
                    "parent": {
                        "id": 1,
                        "type": "probedevice",
                        "name": "Probe"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PrtgObjectsResponse.self, from: json)
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.items[0].kind, .probedevice)
        XCTAssertEqual(response.items[1].status, .down)
    }

    func testDecodeObjectWithMinimalFields() throws {
        let json = """
        {
            "id": 99,
            "name": "Minimal",
            "kind": "group"
        }
        """.data(using: .utf8)!

        let object = try JSONDecoder().decode(PrtgObject.self, from: json)
        XCTAssertEqual(object.id, 99)
        XCTAssertNil(object.status)
        XCTAssertNil(object.message)
        XCTAssertNil(object.parent)
        XCTAssertNil(object.sensorStatusSummary)
    }

    // MARK: - Status Properties

    func testStatusSeverityOrdering() {
        let ordered: [SensorStatus] = [.down, .partialdown, .warning, .unusual, .unknown, .paused, .up]
        for i in 0..<ordered.count - 1 {
            XCTAssertLessThanOrEqual(
                ordered[i].severity, ordered[i + 1].severity,
                "\(ordered[i]) should be at least as severe as \(ordered[i + 1])"
            )
        }
    }

    func testStatusSymbolNames() {
        for status in SensorStatus.allCases {
            XCTAssertFalse(status.symbolName.isEmpty, "\(status) should have a symbol name")
        }
    }
}
