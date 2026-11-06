import XCTest
@testable import PRTGBar

final class AlertEngineTests: XCTestCase {

    // MARK: - Helpers

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    private func snap(
        _ id: Int, _ status: SensorStatus, device: Int = 100, deviceName: String = "web-01",
        project: String = "Kunde A", ack: Bool = false, message: String? = nil
    ) -> SensorSnapshot {
        SensorSnapshot(id: id, name: "Sensor \(id)", deviceId: device, deviceName: deviceName,
                       projectName: project, status: status, isAcknowledged: ack, message: message)
    }

    private func engine(_ configure: (inout AlertConfig) -> Void = { _ in }) -> AlertEngine {
        var config = AlertConfig()
        configure(&config)
        return AlertEngine(config: config)
    }

    // MARK: - Tests

    func testFirstSnapshotProducesNoAlerts() {
        var sut = engine { $0.alertOnWarning = true; $0.extraChecks = 0 }
        let snapshot = [snap(1, .down), snap(2, .warning), snap(3, .up)]
        XCTAssertEqual(sut.process(snapshot, at: at(0)), [])
        XCTAssertEqual(sut.process(snapshot, at: at(1)), [])
    }

    func testDownAlertsAfterOneExtraCheck() {
        var sut = engine()
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(0)), [])
        XCTAssertEqual(sut.process([snap(1, .down, message: "Timeout")], at: at(1)), [])
        let alerts = sut.process([snap(1, .down, message: "Timeout")], at: at(2))
        XCTAssertEqual(alerts, [Alert(kind: .down, title: "web-01: Sensor 1 is down", body: "Timeout",
                                      sensorIds: [1], deviceId: 100, threadId: "device-100", playSound: true)])
        XCTAssertEqual(sut.process([snap(1, .down, message: "Timeout")], at: at(3)), [])
    }

    func testZeroExtraChecksAlertsImmediately() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        let alerts = sut.process([snap(1, .partialdown)], at: at(1))
        XCTAssertEqual(alerts.map(\.kind), [.down])
        XCTAssertEqual(alerts.first?.body, "")
    }

    func testGroupsPerDevice() {
        var sut = engine { $0.extraChecks = 0 }
        let ids = [1, 2, 3, 4]
        _ = sut.process(ids.map { snap($0, .up) } + [snap(5, .up, device: 200, deviceName: "db-01")], at: at(0))
        let alerts = sut.process(
            ids.map { snap($0, .down) } + [snap(5, .down, device: 200, deviceName: "db-01")], at: at(1))
        XCTAssertEqual(alerts.count, 2)
        let web = alerts.first { $0.deviceId == 100 }
        XCTAssertEqual(web?.title, "web-01: 4 sensors down")
        XCTAssertEqual(web?.body, "Sensor 1, Sensor 2, Sensor 3, Sensor 4")
        XCTAssertEqual(web?.sensorIds, ids)
        XCTAssertEqual(web?.threadId, "device-100")
        XCTAssertEqual(alerts.first { $0.deviceId == 200 }?.title, "db-01: Sensor 5 is down")
    }

    func testGroupsPerProject() {
        var sut = engine { $0.extraChecks = 0; $0.combine = .perProject }
        _ = sut.process([snap(2, .up), snap(1, .up, device: 200, deviceName: "db-01")], at: at(0))
        let alerts = sut.process([snap(2, .down), snap(1, .down, device: 200, deviceName: "db-01")], at: at(1))
        XCTAssertEqual(alerts, [Alert(kind: .down, title: "Kunde A: 2 sensors down", body: "Sensor 1, Sensor 2",
                                      sensorIds: [1, 2], deviceId: 200, threadId: "project-Kunde A",
                                      playSound: true)])
    }

    func testRecoveryOnlyAfterAlert() {
        var sut = engine()
        _ = sut.process([snap(1, .up), snap(2, .up)], at: at(0))
        _ = sut.process([snap(1, .down), snap(2, .down)], at: at(1))
        XCTAssertEqual(sut.process([snap(1, .down), snap(2, .up)], at: at(2)).map(\.kind), [.down])
        let alerts = sut.process([snap(1, .up), snap(2, .up)], at: at(3))
        XCTAssertEqual(alerts, [Alert(kind: .recovery, title: "web-01: Sensor 1 is OK again", body: "",
                                      sensorIds: [1], deviceId: 100, threadId: "device-100", playSound: false)])
    }

    func testMissingSensorDoesNotRecover() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(3)), [])
    }

    func testFlappingSendsOneNoticeThenSilence() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        var alerts: [Alert] = []
        for minute in 1...6 {
            alerts += sut.process([snap(1, minute % 2 == 1 ? .down : .up)], at: at(Double(minute)))
        }
        XCTAssertEqual(alerts.map(\.kind), [.down, .recovery, .down, .recovery, .down, .flapping])
        XCTAssertEqual(alerts.last, Alert(kind: .flapping, title: "web-01: Sensor 1 is flapping",
                                          body: "6 changes in 15 min. Muted until it settles.",
                                          sensorIds: [1], deviceId: 100, threadId: "device-100",
                                          playSound: false))
        for minute in 7...12 {
            XCTAssertEqual(sut.process([snap(1, minute % 2 == 1 ? .down : .up)], at: at(Double(minute))), [])
        }
    }

    func testFlappingEndsAfterCalmPeriod() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        for minute in 1...12 {
            _ = sut.process([snap(1, minute % 2 == 1 ? .down : .up)], at: at(Double(minute)))
        }
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(20)), [])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(27)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(28)).map(\.kind), [.down])
    }

    func testFlapSettlingInDownAlertsOnce() {
        var sut = engine { $0.reminderInterval = 1800 }
        _ = sut.process([snap(1, .up)], at: at(0))
        for minute in 1...13 {
            _ = sut.process([snap(1, minute % 2 == 1 ? .down : .up)], at: at(Double(minute)))
        }
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(20)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(28)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(29)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(30)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(59)).map(\.kind), [.reminder])
    }

    func testPausedEndsEpisodeWithoutRecovery() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .paused)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(3)), [])
    }

    func testUnknownEndsEpisodeWithoutRecovery() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .unknown)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(3)), [])
    }

    func testDownThenWarningThenUpRecoversOnce() {
        var sut = engine { $0.extraChecks = 0; $0.alertOnWarning = true }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .warning)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(3)).map(\.kind), [.recovery])
    }

    func testDownWarningDownAlertsOnce() {
        var sut = engine { $0.alertOnWarning = true }
        _ = sut.process([snap(1, .up)], at: at(0))
        var kinds: [AlertKind] = []
        for (minute, status) in [SensorStatus.down, .down, .warning, .warning, .down, .down].enumerated() {
            kinds += sut.process([snap(1, status)], at: at(Double(minute + 1))).map(\.kind)
        }
        XCTAssertEqual(kinds, [.down])
    }

    func testWarningEscalatingToDownAlertsDown() {
        var sut = engine { $0.extraChecks = 0; $0.alertOnWarning = true }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .warning)], at: at(1)).map(\.kind), [.warning])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(2)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(3)).map(\.kind), [.recovery])
    }

    func testAcknowledgeEndsEpisodeWithoutRecovery() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .down, ack: true)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(3)), [])
    }

    func testUnacknowledgeWhileDownAlertsAgain() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .down, ack: true)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(3)).map(\.kind), [.down])
    }

    func testSensorFirstSeenAfterBaselineIsKnown() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .up), snap(2, .down)], at: at(1)), [])
        XCTAssertEqual(sut.process([snap(1, .up), snap(2, .down)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .up), snap(2, .up)], at: at(3)), [])
        XCTAssertEqual(sut.process([snap(1, .up), snap(2, .down)], at: at(4)).map(\.sensorIds), [[2]])
    }

    func testCombineNeverAlertsPerSensor() {
        var sut = engine { $0.extraChecks = 0; $0.combine = .never }
        _ = sut.process([snap(1, .up), snap(2, .up)], at: at(0))
        let alerts = sut.process([snap(2, .down), snap(1, .down)], at: at(1))
        XCTAssertEqual(alerts.map(\.title), ["web-01: Sensor 1 is down", "web-01: Sensor 2 is down"])
        XCTAssertEqual(alerts.map(\.threadId), ["device-100", "device-100"])
    }

    func testNoRecoveryWhenDisabled() {
        var sut = engine { $0.extraChecks = 0; $0.alertOnRecovery = false }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(2)), [])
    }

    func testGroupedRecoveryCopy() {
        var sut = engine { $0.extraChecks = 0 }
        _ = sut.process([snap(1, .up), snap(2, .up)], at: at(0))
        _ = sut.process([snap(1, .down), snap(2, .down)], at: at(1))
        let alerts = sut.process([snap(1, .up), snap(2, .up)], at: at(2))
        XCTAssertEqual(alerts, [Alert(kind: .recovery, title: "web-01: 2 sensors OK again", body: "Sensor 1, Sensor 2",
                                      sensorIds: [1, 2], deviceId: 100, threadId: "device-100", playSound: false)])
    }

    func testReminderRepeats() {
        var sut = engine { $0.extraChecks = 0; $0.reminderInterval = 1800 }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)).map(\.kind), [.down])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(20)), [])
        let reminder = sut.process([snap(1, .down, message: "Timeout")], at: at(31))
        XCTAssertEqual(reminder, [Alert(kind: .reminder, title: "Still down: web-01 Sensor 1", body: "Timeout",
                                        sensorIds: [1], deviceId: 100, threadId: "device-100", playSound: true)])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(45)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(61)).map(\.kind), [.reminder])
    }

    func testSnoozeSuppressesButKeepsState() {
        var sut = engine { $0.reminderInterval = 1800; $0.snoozedUntil = self.at(10) }
        _ = sut.process([snap(1, .up)], at: at(0))
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(1)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(2)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(11)), [])
        XCTAssertEqual(sut.process([snap(1, .down)], at: at(32)).map(\.kind), [.reminder])
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(33)).map(\.kind), [.recovery])
    }

    func testAcknowledgedSkipped() {
        var sut = engine { $0.extraChecks = 0; $0.reminderInterval = 1800 }
        _ = sut.process([snap(1, .up), snap(2, .up, device: 200, deviceName: "db-01")], at: at(0))
        let alerts = sut.process(
            [snap(1, .down, ack: true), snap(2, .down, device: 200, deviceName: "db-01")], at: at(1))
        XCTAssertEqual(alerts.map(\.sensorIds), [[2]])
        XCTAssertEqual(sut.process(
            [snap(1, .down, ack: true), snap(2, .down, device: 200, deviceName: "db-01", ack: true)],
            at: at(40)), [])
    }

    func testWarningDisabledByDefault() {
        var sut = engine()
        _ = sut.process([snap(1, .up)], at: at(0))
        for minute in 1...4 {
            XCTAssertEqual(sut.process([snap(1, .warning)], at: at(Double(minute))), [])
        }
        XCTAssertEqual(sut.process([snap(1, .up)], at: at(5)), [])

        var enabled = engine { $0.alertOnWarning = true; $0.extraChecks = 0 }
        _ = enabled.process([snap(1, .up)], at: at(0))
        let alerts = enabled.process([snap(1, .unusual, message: "Slow")], at: at(1))
        XCTAssertEqual(alerts, [Alert(kind: .warning, title: "web-01: Sensor 1 has a warning", body: "Slow",
                                      sensorIds: [1], deviceId: 100, threadId: "device-100", playSound: false)])
    }
}
