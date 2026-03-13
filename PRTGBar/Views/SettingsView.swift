import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                case .connection:
                    connectionTab
                case .about:
                    AboutView()
                }
            }
        }
        .frame(width: 420)
        .onAppear {
            serverURL = appState.serverURL
            apiKey = appState.apiKey
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
            refreshSection
            notificationSection
            appearanceSection
        }
        .formStyle(.grouped)
        .scrollDisabled(false)
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
            Toggle("Enable notifications", isOn: $appState.notifyOnStatusChange)
                .onChange(of: appState.notifyOnStatusChange) { _, newValue in
                    if newValue {
                        appState.requestNotificationPermission()
                    }
                }

            if appState.notifyOnStatusChange {
                Toggle("Notify on sensor down", isOn: $appState.notifyOnDown)
                Toggle("Notify on warnings", isOn: $appState.notifyOnWarning)
                Toggle("Play notification sound", isOn: $appState.notificationSound)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Toggle("Show badge count in menu bar", isOn: $appState.showBadgeCount)
            Toggle("Show all probes section", isOn: $appState.showAllProbes)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }

    // MARK: - Connection Tab

    private var connectionTab: some View {
        Form {
            serverSection

            Section("SSL / TLS") {
                Toggle("Accept self-signed certificates", isOn: $appState.acceptSelfSignedCerts)
                Text("Enable this if your PRTG server uses a self-signed SSL certificate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
    case connection
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .connection: "Connection"
        case .about: "About"
        }
    }
}
