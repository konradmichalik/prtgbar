import UserNotifications

enum NotificationDispatcher {
    static let categoryId = "SENSOR_ALERT"
    static let acknowledgeAction = "ACKNOWLEDGE"
    static let openAction = "OPEN"

    static func registerCategories(center: UNUserNotificationCenter) {
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [
                UNNotificationAction(identifier: acknowledgeAction, title: "Acknowledge"),
                UNNotificationAction(identifier: openAction, title: "Open", options: .foreground)
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    static func content(for alert: Alert, soundEnabled: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = alert.threadId
        content.userInfo = ["sensorIds": alert.sensorIds, "deviceId": alert.deviceId]
        content.interruptionLevel = alert.kind == .recovery ? .passive : .active
        if alert.playSound && soundEnabled { content.sound = .default }
        if alert.kind != .recovery && alert.kind != .flapping { content.categoryIdentifier = categoryId }
        return content
    }

    static func deliver(_ alerts: [Alert], soundEnabled: Bool, center: UNUserNotificationCenter = .current()) {
        for alert in alerts {
            let request = UNNotificationRequest(
                identifier: "\(alert.threadId)-\(UUID())",
                content: content(for: alert, soundEnabled: soundEnabled),
                trigger: nil
            )
            center.add(request)
        }
    }
}
