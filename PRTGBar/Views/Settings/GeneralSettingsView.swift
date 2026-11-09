import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show count next to the icon", isOn: $appState.showBadgeCount)
                Toggle("Show warning indicator", isOn: $appState.showWarningIndicator)
            }
            Section("Menu") {
                Picker("Sort problems", selection: $appState.problemSort) {
                    Text("Newest first").tag(ProblemSort.newestFirst.rawValue)
                    Text("Longest first").tag(ProblemSort.longestFirst.rawValue)
                    Text("By device").tag(ProblemSort.byDevice.rawValue)
                }
                Toggle("Show 24 h history in sensor details", isOn: $appState.showHistory)
                Picker("Projects are", selection: $appState.projectLevel) {
                    Text("Top-level groups").tag(1)
                    Text("Second-level groups").tag(2)
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onChange(of: appState.problemSort) { _, _ in appState.updateMenuModel() }
        .onChange(of: appState.showHistory) { _, _ in appState.updateMenuModel() }
        .onChange(of: appState.projectLevel) { _, _ in appState.updateMenuModel() }
        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
