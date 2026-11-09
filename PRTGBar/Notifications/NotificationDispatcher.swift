import UserNotifications

enum NotificationDispatcher {
    static let categoryId = "SENSOR_ALERT"
    static let warningCategoryId = "SENSOR_WARNING"
    static let acknowledgeAction = "ACKNOWLEDGE"
    static let openAction = "OPEN"

    /// PRTG only acknowledges sensors in a down state, so warnings offer Open alone.
    static var categories: Set<UNNotificationCategory> {
        let acknowledge = UNNotificationAction(identifier: acknowledgeAction, title: "Acknowledge")
        let open = UNNotificationAction(identifier: openAction, title: "Open in PRTG", options: .foreground)
        return [
            UNNotificationCategory(identifier: categoryId, actions: [acknowledge, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: warningCategoryId, actions: [open], intentIdentifiers: []),
        ]
    }

    static func registerCategories(center: UNUserNotificationCenter) {
        center.setNotificationCategories(categories)
    }

    /// Object ids are only unique per server, so actions check this against the current server first.
    static func serverKey(_ serverURL: String) -> String {
        serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    static func content(for alert: Alert, soundEnabled: Bool, server: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = alert.threadId
        content.userInfo = ["sensorIds": alert.sensorIds, "deviceId": alert.deviceId, "server": server]
        content.interruptionLevel = alert.kind == .recovery ? .passive : .active
        if alert.playSound && soundEnabled { content.sound = .default }
        switch alert.kind {
        case .down, .reminder: content.categoryIdentifier = categoryId
        case .warning: content.categoryIdentifier = warningCategoryId
        case .recovery, .flapping: break
        }
        return content
    }

    static func deliver(
        _ alerts: [Alert], soundEnabled: Bool, server: String, center: UNUserNotificationCenter = .current()
    ) {
        for alert in alerts {
            let request = UNNotificationRequest(
                identifier: "\(alert.threadId)-\(UUID())",
                content: content(for: alert, soundEnabled: soundEnabled, server: server),
                trigger: nil
            )
            center.add(request)
        }
    }
}
