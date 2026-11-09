import SwiftUI

struct ServerSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var connectionStatus: ConnectionStatus = .idle

    private enum ConnectionStatus {
        case idle, testing, success, failed
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $serverURL, prompt: Text("prtg.example.com"))
                    .onChange(of: serverURL) { _, newValue in
                        guard newValue != appState.serverURL else { return }
                        appState.serverURL = newValue
                        appState.credentialsDidChange()
                    }
                SecureField("API Key", text: $apiKey, prompt: Text("API token from PRTG"))
                    .onChange(of: apiKey) { _, newValue in
                        guard newValue != appState.apiKey else { return }
                        appState.apiKey = newValue
                        appState.credentialsDidChange()
                    }
                testRow
                if connectionStatus == .failed, let error = appState.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Polling") {
                Picker("Poll interval", selection: $appState.refreshInterval) {
                    ForEach(SettingsMigration.allowedIntervals, id: \.self) { interval in
                        Text(Self.intervalLabel(interval)).tag(interval)
                    }
                }
                .onChange(of: appState.refreshInterval) { _, _ in appState.startPolling() }
            }
            Section("Security") {
                Toggle("Accept self-signed certificates", isOn: $appState.acceptSelfSignedCerts)
                Text("Enable this if your PRTG server uses a self-signed SSL certificate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            serverURL = appState.serverURL
            apiKey = appState.apiKey
        }
    }

    private var testRow: some View {
        HStack {
            Button("Test Connection", action: testConnection)
                .disabled(serverURL.isEmpty || apiKey.isEmpty || connectionStatus == .testing)
            Spacer()
            switch connectionStatus {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView().controlSize(.small)
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private static func intervalLabel(_ seconds: Double) -> String {
        seconds < 60 ? MenuText.count(Int(seconds), "second") : MenuText.count(Int(seconds) / 60, "minute")
    }

    private func testConnection() {
        connectionStatus = .testing
        Task {
            let success = await appState.testConnection()
            connectionStatus = success ? .success : .failed
            if success {
                appState.startPolling()
            }
        }
    }
}
