import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var connectionStatus: ConnectionStatus = .idle

    enum ConnectionStatus {
        case idle, testing, success, failed
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 60)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Group {
                switch selectedTab {
                case .general:
                    generalTab
                case .about:
                    AboutView()
                }
            }
            .frame(height: selectedTab == .general ? 280 : 300)
        }
        .frame(width: 400)
        .onAppear {
            serverURL = appState.serverURL
            apiKey = appState.apiKey
            // Ensure settings window appears above all other windows (LSUIElement app)
            DispatchQueue.main.async {
                for window in NSApp.windows where window.title == "Settings" || window.identifier?.rawValue.contains("settings") == true {
                    window.level = .floating
                    window.orderFrontRegardless()
                }
            }
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            serverSection
            refreshSection
            notificationSection
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    // MARK: - Server

    private var serverSection: some View {
        Section("Server") {
            TextField("Server URL", text: $serverURL, prompt: Text("prtg.example.com"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: serverURL) { _, newValue in
                    appState.serverURL = newValue
                }

            SecureField("API Key", text: $apiKey, prompt: Text("Bearer token from PRTG"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: apiKey) { _, newValue in
                    appState.apiKey = newValue
                }

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(serverURL.isEmpty || apiKey.isEmpty || connectionStatus == .testing)

                Spacer()

                switch connectionStatus {
                case .idle:
                    EmptyView()
                case .testing:
                    ProgressView()
                        .controlSize(.small)
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

            if connectionStatus == .failed, let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        Section("Refresh") {
            Picker("Interval", selection: $appState.refreshInterval) {
                Text("30 seconds").tag(30.0)
                Text("1 minute").tag(60.0)
                Text("2 minutes").tag(120.0)
                Text("5 minutes").tag(300.0)
            }
            .onChange(of: appState.refreshInterval) { _, _ in
                appState.startPolling()
            }
        }
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        Section("Notifications") {
            Toggle("Notify when sensor goes down", isOn: $appState.notifyOnStatusChange)
                .onChange(of: appState.notifyOnStatusChange) { _, newValue in
                    if newValue {
                        appState.requestNotificationPermission()
                    }
                }
        }
    }

    // MARK: - Actions

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

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .about: "About"
        }
    }
}
