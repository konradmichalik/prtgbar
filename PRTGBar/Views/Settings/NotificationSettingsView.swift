import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Alert me when") {
                Toggle("A sensor goes Down", isOn: $appState.notifyOnDown)
                Toggle("A sensor shows Warning or Unusual", isOn: $appState.notifyOnWarning)
                Toggle("A sensor is Up again", isOn: $appState.notifyOnRecovery)
            }
            Section("Delivery") {
                Picker("Wait before alerting", selection: $appState.alertExtraChecks) {
                    Text("Alert at once").tag(0)
                    Text("After 1 more check").tag(1)
                    Text("After 2 more checks").tag(2)
                }
                Picker("Combine alerts", selection: $appState.combineAlerts) {
                    Text("Never").tag(CombineMode.never.rawValue)
                    Text("Per device").tag(CombineMode.perDevice.rawValue)
                    Text("Per group").tag(CombineMode.perProject.rawValue)
                }
                Toggle("Mute flapping sensors", isOn: $appState.muteFlapping)
                Toggle("Skip acknowledged and paused", isOn: $appState.skipAcknowledgedAndPaused)
                Toggle("Play sound", isOn: $appState.notificationSound)
                Picker("Remind while still down", selection: $appState.reminderInterval) {
                    Text("Never").tag(0.0)
                    Text("Every 30 minutes").tag(1800.0)
                    Text("Every hour").tag(3600.0)
                    Text("Every 4 hours").tag(14400.0)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appState.notifyOnDown) { _, on in requestPermissionIfNeeded(on) }
        .onChange(of: appState.notifyOnWarning) { _, on in requestPermissionIfNeeded(on) }
        .onChange(of: appState.notifyOnRecovery) { _, on in requestPermissionIfNeeded(on) }
    }

    private func requestPermissionIfNeeded(_ enabled: Bool) {
        if enabled {
            appState.requestNotificationPermission()
        }
    }
}
