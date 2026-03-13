import SwiftUI

struct MenubarView: View {
    @EnvironmentObject var appState: AppState

    @Environment(\.openSettings) private var openSettings
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var hideAcknowledged = false
    @State private var showSearch = false
    @State private var statusFilter: StatusPillFilter?

    var body: some View {
        VStack(spacing: 0) {
            header
            if appState.isConfigured && !appState.treeNodes.isEmpty {
                statusPillsRow
                if showSearch {
                    searchField
                }
            }
            Divider()
            content
            Divider()
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            (Text("PRTG").font(.headline) + Text("bar").font(.caption).baselineOffset(6))
                .foregroundStyle(.primary)

            Spacer()

            headerButtons
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var statusPillsRow: some View {
        HStack(spacing: 4) {
            let counts = appState.statusCounts
            statusPill(count: counts.up, color: .green, filter: .up)
            if counts.down > 0 {
                statusPill(count: counts.down, color: .red, filter: .down)
            }
            if counts.warning > 0 {
                statusPill(count: counts.warning, color: .orange, filter: .warning)
            }
            if counts.paused > 0 {
                statusPill(count: counts.paused, color: .secondary, filter: .paused)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func statusPill(count: Int, color: Color, filter: StatusPillFilter) -> some View {
        let isActive = statusFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                statusFilter = isActive ? nil : filter
            }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isActive ? color.opacity(0.15) : .clear)
            )
        }
        .buttonStyle(.borderless)
    }

    private var headerButtons: some View {
        HStack(spacing: 10) {
            if appState.isConfigured && !appState.treeNodes.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                } label: {
                    Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(showSearch ? Color.accentColor : Color.secondary)
                .help("Search")
            }

            Button {
                hideAcknowledged.toggle()
            } label: {
                Image(systemName: hideAcknowledged ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(hideAcknowledged ? Color.accentColor : Color.secondary)
            .help(hideAcknowledged ? "Show acknowledged" : "Hide acknowledged")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField("Search sensors...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.04))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                    searchText: searchText,
                    hideAcknowledged: hideAcknowledged,
                    showAllProbes: appState.showAllProbes,
                    statusFilter: statusFilter
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
        HStack(spacing: 8) {
            if let error = appState.lastError {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let updated = appState.lastUpdated {
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
                    .font(.system(size: 10))
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

            HStack(spacing: 12) {
                if !appState.serverURL.isEmpty {
                    Button {
                        openPrtgDashboard(serverURL: appState.serverURL)
                    } label: {
                        Image("MenubarIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 13, height: 13)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Open PRTG")
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Quit PRTGBar")
            }
        }
        .padding(.horizontal, 12)
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
