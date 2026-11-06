import XCTest
import UserNotifications
@testable import PRTGBar

final class NotificationDispatcherTests: XCTestCase {

    private func alert(_ kind: AlertKind, sensorIds: [Int] = [1], playSound: Bool = false) -> Alert {
        Alert(kind: kind, title: "Web: Ping is down", body: "timeout", sensorIds: sensorIds,
              deviceId: 7, threadId: "device-7", playSound: playSound)
    }

    func testRecoveryIsPassiveWithoutSound() {
        let content = NotificationDispatcher.content(for: alert(.recovery), soundEnabled: true)
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertNil(content.sound)
    }

    func testDownHasSoundWhenEnabled() {
        let down = alert(.down, playSound: true)
        let loud = NotificationDispatcher.content(for: down, soundEnabled: true)
        XCTAssertEqual(loud.interruptionLevel, .active)
        XCTAssertNotNil(loud.sound)
        XCTAssertNil(NotificationDispatcher.content(for: down, soundEnabled: false).sound)
    }

    func testUserInfoCarriesAllSensorIds() {
        let content = NotificationDispatcher.content(for: alert(.down, sensorIds: [1, 2, 3]), soundEnabled: true)
        XCTAssertEqual(content.userInfo["sensorIds"] as? [Int], [1, 2, 3])
        XCTAssertEqual(content.userInfo["deviceId"] as? Int, 7)
    }

    func testThreadIdentifierPerDevice() {
        let content = NotificationDispatcher.content(for: alert(.warning), soundEnabled: true)
        XCTAssertEqual(content.threadIdentifier, "device-7")
        XCTAssertEqual(content.categoryIdentifier, NotificationDispatcher.categoryId)
    }

    func testRecoveryHasNoActionsCategory() {
        let content = NotificationDispatcher.content(for: alert(.recovery), soundEnabled: true)
        XCTAssertEqual(content.categoryIdentifier, "")
    }
}
