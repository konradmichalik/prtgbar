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
                .frame(width: 380, height: 520)
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
        let hasSound = notification.request.content.sound != nil
        handler(hasSound ? [.banner, .sound] : [.banner])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notificationHandler = NotificationHandler()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationHandler
        installRightClickMenu()
    }

    private func installRightClickMenu() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let window = event.window,
                  String(describing: type(of: window)).contains("StatusBar") else {
                return event
            }
            showStatusItemMenu(from: window)
            return nil
        }
    }

    private func showStatusItemMenu(from window: NSWindow) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open PRTGBar", action: #selector(openPopover), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PRTGBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: window.contentView)
    }

    @objc private func openPopover() {
        // Simulate a left-click on the status item to open the popover
        if let button = NSApp.windows
            .first(where: { String(describing: type(of: $0)).contains("StatusBar") })?
            .contentView?.subviews.first as? NSControl {
            button.performClick(nil)
        }
    }
}
