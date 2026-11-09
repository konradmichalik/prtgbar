import XCTest
import UserNotifications
@testable import PRTGBar

final class NotificationDispatcherTests: XCTestCase {

    private func alert(_ kind: AlertKind, sensorIds: [Int] = [1], playSound: Bool = false) -> Alert {
        Alert(kind: kind, title: "Web: Ping is down", body: "timeout", sensorIds: sensorIds,
              deviceId: 7, threadId: "device-7", playSound: playSound)
    }

    func testRecoveryIsPassiveWithoutSound() {
        let content = NotificationDispatcher.content(for: alert(.recovery), soundEnabled: true, server: "")
        XCTAssertEqual(content.interruptionLevel, .passive)
        XCTAssertNil(content.sound)
    }

    func testDownHasSoundWhenEnabled() {
        let down = alert(.down, playSound: true)
        let loud = NotificationDispatcher.content(for: down, soundEnabled: true, server: "")
        XCTAssertEqual(loud.interruptionLevel, .active)
        XCTAssertNotNil(loud.sound)
        XCTAssertNil(NotificationDispatcher.content(for: down, soundEnabled: false, server: "").sound)
    }

    func testUserInfoCarriesAllSensorIds() {
        let content = NotificationDispatcher.content(for: alert(.down, sensorIds: [1, 2, 3]), soundEnabled: true, server: "")
        XCTAssertEqual(content.userInfo["sensorIds"] as? [Int], [1, 2, 3])
        XCTAssertEqual(content.userInfo["deviceId"] as? Int, 7)
    }

    func testUserInfoCarriesServer() {
        let content = NotificationDispatcher.content(for: alert(.down), soundEnabled: true,
                                                     server: NotificationDispatcher.serverKey(" https://prtg.example.com/ "))
        XCTAssertEqual(content.userInfo["server"] as? String, "https://prtg.example.com")
        XCTAssertEqual(NotificationDispatcher.serverKey("https://PRTG.example.com"), "https://prtg.example.com")
    }

    func testThreadIdentifierPerDevice() {
        let content = NotificationDispatcher.content(for: alert(.warning), soundEnabled: true, server: "")
        XCTAssertEqual(content.threadIdentifier, "device-7")
    }

    func testOnlyDownAlertsOfferAcknowledge() {
        let down = NotificationDispatcher.content(for: alert(.down), soundEnabled: true, server: "")
        let reminder = NotificationDispatcher.content(for: alert(.reminder), soundEnabled: true, server: "")
        let warning = NotificationDispatcher.content(for: alert(.warning), soundEnabled: true, server: "")
        XCTAssertEqual(down.categoryIdentifier, NotificationDispatcher.categoryId)
        XCTAssertEqual(reminder.categoryIdentifier, NotificationDispatcher.categoryId)
        XCTAssertEqual(warning.categoryIdentifier, NotificationDispatcher.warningCategoryId)

        let actions = Dictionary(uniqueKeysWithValues: NotificationDispatcher.categories.map {
            ($0.identifier, $0.actions.map(\.title))
        })
        XCTAssertEqual(actions[NotificationDispatcher.categoryId], ["Acknowledge", "Open in PRTG"])
        XCTAssertEqual(actions[NotificationDispatcher.warningCategoryId], ["Open in PRTG"])
    }

    func testRecoveryHasNoActionsCategory() {
        let content = NotificationDispatcher.content(for: alert(.recovery), soundEnabled: true, server: "")
        XCTAssertEqual(content.categoryIdentifier, "")
    }
}
