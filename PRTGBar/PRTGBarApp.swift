import SwiftUI
import UserNotifications

@main
struct PRTGBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenubarView()
                .environmentObject(appState)
                .frame(width: 400, height: 520)
                .task { appState.onLaunch() }
        } label: {
            Image("MenubarIcon")
            if let count = appState.badgeCount {
                Text("\(count)")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notificationHandler = NotificationHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationHandler
    }
}
