import SwiftUI
import UserNotifications

@main
struct PRTGBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Declared first so SwiftUI creates it at launch; it only hosts SettingsOpener.
        Window("PRTGBar", id: SettingsOpener.windowId) {
            SettingsOpener()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

/// AppKit cannot open the SwiftUI Settings scene reliably on macOS 14+, so the status item
/// posts a notification and this invisible view calls `openSettings` on its behalf.
struct SettingsOpener: View {
    static let windowId = "settings-opener"

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .prtgBarOpenSettings)) { _ in
                NSApp.activate()
                openSettings()
            }
            .onAppear(perform: hideHostWindow)
    }

    private func hideHostWindow() {
        let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(Self.windowId) == true }
        guard let window else { return }
        window.styleMask = [.borderless]
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: 1, height: 1), display: false)
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
    let appState = AppState()
    private let notificationHandler = NotificationHandler()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationHandler
        statusItemController = StatusItemController(appState: appState)
        appState.onLaunch()
    }
}
