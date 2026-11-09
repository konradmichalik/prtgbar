import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = SettingsTab.initial(
        serverURL: UserDefaults.standard.string(forKey: "serverURL") ?? ""
    )

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ServerSettingsView()
                .tabItem { Label("Server", systemImage: "server.rack") }
                .tag(SettingsTab.server)
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 460, height: 400)
        .onAppear(perform: raiseWindow)
    }

    private func raiseWindow() {
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "Settings" || window.identifier?.rawValue.contains("settings") == true {
                window.level = .floating
                window.orderFrontRegardless()
            }
        }
    }
}

enum SettingsTab: Hashable {
    case general, server, notifications, about

    /// Without a server there is nothing else worth configuring, so the window opens on Server.
    /// Decided once at creation: recomputing it would jump away while the first URL is typed.
    static func initial(serverURL: String) -> SettingsTab {
        serverURL.isEmpty ? .server : .general
    }
}
