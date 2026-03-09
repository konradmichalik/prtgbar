import SwiftUI

struct MenubarView: View {
    @EnvironmentObject var appState: AppState

    @Environment(\.openSettings) private var openSettings
    @State private var isRefreshing = false
    @AppStorage("groupByDevice") private var groupByDevice = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if appState.isConfigured && appState.treeNodes.isEmpty == false {
                statusSummaryBar
            }
            Divider()
            content
            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("PRTGBar")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            if let error = appState.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }

            Button {
                groupByDevice.toggle()
            } label: {
                Image(systemName: groupByDevice ? "list.bullet" : "list.bullet.indent")
            }
            .buttonStyle(.borderless)
            .help(groupByDevice ? "Flat list" : "Group by device")

            if !appState.serverURL.isEmpty {
                Button {
                    openPrtgDashboard(serverURL: appState.serverURL)
                } label: {
                    Image(systemName: "globe")
                }
                .buttonStyle(.borderless)
                .help("Open PRTG")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Status Summary

    private var statusSummaryBar: some View {
        HStack(spacing: 12) {
            let counts = appState.statusCounts
            statusPill(count: counts.up, status: .up)
            statusPill(count: counts.down, status: .down)
            statusPill(count: counts.warning, status: .warning)
            if counts.paused > 0 {
                statusPill(count: counts.paused, status: .paused)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func statusPill(count: Int, status: SensorStatus) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if !appState.isConfigured || (appState.serverURL.isEmpty || appState.apiKey.isEmpty) {
                emptyView
            } else if appState.isLoading && appState.treeNodes.isEmpty {
                loadingView
            } else if appState.treeNodes.isEmpty {
                noDataView
            } else {
                ProblemsView(
                    treeNodes: appState.treeNodes,
                    statusCounts: appState.statusCounts,
                    serverURL: appState.serverURL,
                    problemTimestamps: appState.problemTimestamps,
                    groupByDevice: groupByDevice
                )
            }
        }
        .frame(maxHeight: 450)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
            Text("Loading sensors...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No server configured")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var noDataView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No sensors found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let updated = appState.lastUpdated {
                Text(relativeTimeString(from: updated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button {
                withAnimation { isRefreshing = true }
                Task {
                    await appState.refresh()
                    withAnimation { isRefreshing = false }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(appState.isLoading)

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Quit PRTGBar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Updated just now" }
        let minutes = seconds / 60
        if minutes == 1 { return "Updated 1 min ago" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours == 1 { return "Updated 1 hour ago" }
        return "Updated \(hours) hours ago"
    }
}
