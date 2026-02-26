import SwiftUI

struct MenubarView: View {
    @EnvironmentObject var appState: AppState

    @Environment(\.openSettings) private var openSettings
    @State private var isRefreshing = false

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
                withAnimation { isRefreshing = true }
                Task {
                    await appState.refresh()
                    withAnimation { isRefreshing = false }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(appState.isLoading)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
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
                sensorTree
            }
        }
        .frame(maxHeight: 450)
    }

    private var sensorTree: some View {
        List {
            ForEach(appState.treeNodes) { node in
                ObjectSection(
                    node: node,
                    serverURL: appState.serverURL,
                    depth: 0,
                    autoExpandErrors: appState.autoExpandErrors
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .listRowSeparator(.hidden)
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
                Text("Updated \(updated, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
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
}
