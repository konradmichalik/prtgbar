import XCTest
@testable import PRTGBar

final class PrtgClientTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodeSensorTableCarriesLastValue() throws {
        let json = #"{"sensors":[{"objid":1,"name":"Ping","status_raw":3,"parentid":100,"lastvalue":"8 msec"}]}"#

        let objects = try PrtgClient.decodeTable(Data(json.utf8), kind: .sensor)

        XCTAssertEqual(objects.map(\.lastValue), ["8 msec"])
        XCTAssertEqual(TreeBuilder.buildTree(from: objects).first?.lastValue, "8 msec")
    }

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

    // MARK: - Write Actions

    private func writeURL(_ action: PrtgClient.WriteAction) throws -> URLComponents {
        let url = try PrtgClient.writeActionURL(action, serverURL: "prtg.example.com", token: "tok")
        return try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    private func query(_ components: URLComponents, _ name: String) -> String? {
        components.queryItems?.first { $0.name == name }?.value
    }

    func testPauseIndefinitelyURL() throws {
        let c = try writeURL(.pause(id: 42, minutes: nil))
        XCTAssertEqual(c.path, "/api/pause.htm")
        XCTAssertEqual(query(c, "id"), "42")
        XCTAssertEqual(query(c, "action"), "0")
        XCTAssertEqual(query(c, "apitoken"), "tok")
    }

    func testPauseForMinutesURL() throws {
        let c = try writeURL(.pause(id: 42, minutes: 60))
        XCTAssertEqual(c.path, "/api/pauseobjectfor.htm")
        XCTAssertEqual(query(c, "id"), "42")
        XCTAssertEqual(query(c, "duration"), "60")
    }

    func testPauseURLsCarryNoMessage() throws {
        XCTAssertNil(query(try writeURL(.pause(id: 42, minutes: nil)), "pausemsg"))
        XCTAssertNil(query(try writeURL(.pause(id: 42, minutes: 60)), "pausemsg"))
    }

    func testAcknowledgeURLOmitsMessageWhenNil() throws {
        let c = try writeURL(.acknowledge(id: 7, message: nil))
        XCTAssertEqual(c.path, "/api/acknowledgealarm.htm")
        XCTAssertNil(query(c, "ackmsg"))
    }

    func testWriteActionMapsForbiddenToReadOnlyMessage() {
        guard case .readOnly = PrtgClient.mapWriteError(.unauthorized) else {
            return XCTFail("unauthorized should map to readOnly")
        }
        XCTAssertEqual(
            PrtgClientError.readOnly.errorDescription,
            "This API key is read-only or lacks permission for this action."
        )
        guard case .serverError(500) = PrtgClient.mapWriteError(.serverError(500)) else {
            return XCTFail("other errors stay unchanged")
        }
    }

    // MARK: - Grouped Acknowledge

    func testAckOutcomeAllSucceeded() {
        XCTAssertNil(PrtgClient.ackOutcome([.success(()), .success(())]))
    }

    func testAckOutcomeAllReadOnly() {
        guard case .readOnly = PrtgClient.ackOutcome([.failure(.readOnly), .failure(.readOnly)]) else {
            return XCTFail("all read-only failures should report readOnly")
        }
    }

    func testAckOutcomeSomeFailed() {
        let error = PrtgClient.ackOutcome([.success(()), .failure(.serverError(500)), .failure(.readOnly)])
        XCTAssertEqual(error?.errorDescription, "2 of 3 sensors could not be acknowledged.")
    }

    func testAckOutcomeAllFailedForOtherReasons() {
        let error = PrtgClient.ackOutcome([.failure(.serverError(500)), .failure(.readOnly)])
        XCTAssertEqual(error?.errorDescription, "2 of 2 sensors could not be acknowledged.")
    }

    func testAckOutcomeSingleFailureKeepsItsError() {
        guard case .serverError(500) = PrtgClient.ackOutcome([.failure(.serverError(500))]) else {
            return XCTFail("a single sensor reports its own error")
        }
    }

    // MARK: - Error Body

    func testErrorMessageFromXMLBody() {
        let xml = "<?xml version=\"1.0\"?><prtg><version>24.1</version><error>Sorry, not allowed.</error></prtg>"
        XCTAssertEqual(PrtgClient.errorMessage(from: Data(xml.utf8), token: "tok"), "Sorry, not allowed.")
    }

    func testErrorMessageFromJSONBody() {
        let json = #"{"prtg-version":"24.1","errormessage":"Sorry, not allowed."}"#
        XCTAssertEqual(PrtgClient.errorMessage(from: Data(json.utf8), token: "tok"), "Sorry, not allowed.")
    }

    func testErrorMessageMissingForUnknownBody() {
        XCTAssertNil(PrtgClient.errorMessage(from: Data("<html><body>Bad Request</body></html>".utf8), token: "tok"))
        XCTAssertNil(PrtgClient.errorMessage(from: Data(), token: "tok"))
    }

    func testErrorMessageHidesEchoedToken() {
        let xml = "<prtg><error>Bad request /api/pause.htm?id=1&apitoken=secret123</error></prtg>"
        XCTAssertEqual(
            PrtgClient.errorMessage(from: Data(xml.utf8), token: "secret123"),
            "Bad request /api/pause.htm?id=1&apitoken=…"
        )
    }

    func testServerMessageDescriptionCarriesStatusAndText() {
        XCTAssertEqual(
            PrtgClientError.serverMessage(400, "Sorry, not allowed.").errorDescription,
            "Server returned error 400: Sorry, not allowed."
        )
    }
}
