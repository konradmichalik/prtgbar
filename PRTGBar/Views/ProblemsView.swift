import SwiftUI

struct ProblemsView: View {
    let treeNodes: [TreeNode]
    let statusCounts: StatusSummary
    let serverURL: String
    let problemTimestamps: [Int: Date]
    let searchText: String
    let hideAcknowledged: Bool
    var showAllProbes: Bool = true
    var statusFilter: StatusPillFilter?

    var body: some View {
        let allProblems = ProblemItem.collect(from: treeNodes, fallbackTimestamps: problemTimestamps)
        let filtered = filterProblems(allProblems)
        let errors = filtered.filter { $0.status == .down || $0.status == .partialdown }
        let warnings = filtered.filter { $0.status != .down && $0.status != .partialdown }
        let hasAlerts = !errors.isEmpty || !warnings.isEmpty

        if !hasAlerts && !showAllProbes {
            if allProblems.isEmpty {
                allGoodBanner
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                noMatchView
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    if allProblems.isEmpty {
                        allGoodBanner
                    }
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        alertSections(errors: errors, warnings: warnings)
                        if showAllProbes {
                            if hasAlerts { Divider() }
                            allProbesSection
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - Filter

    private func filterProblems(_ items: [ProblemItem]) -> [ProblemItem] {
        var result = items

        if let statusFilter {
            let allowed = statusFilter.statuses
            result = result.filter { allowed.contains($0.status) }
        }

        if hideAcknowledged {
            result = result.filter { item in
                guard let message = item.message else { return true }
                return !SensorMessage(message).isAcknowledged
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { item in
                item.sensorName.lowercased().contains(query)
                    || item.deviceName.lowercased().contains(query)
                    || (item.groupName?.lowercased().contains(query) ?? false)
                    || (item.message?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    // MARK: - All Good

    private var allGoodBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("All \(statusCounts.total) sensors up")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var allProbesSection: some View {
        AllProbesView(treeNodes: treeNodes, serverURL: serverURL, searchText: searchText, statusFilter: statusFilter)
    }

    // MARK: - No Match

    private var noMatchView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No results")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Alert Sections

    @ViewBuilder
    private func alertSections(errors: [ProblemItem], warnings: [ProblemItem]) -> some View {
        if !errors.isEmpty {
            Section {
                ForEach(Array(errors.enumerated()), id: \.element.id) { index, item in
                    AlertRowView(item: item, serverURL: serverURL)
                    if index < errors.count - 1 {
                        Divider()
                    }
                }
            } header: {
                SectionHeaderView(title: "Critical Errors", count: errors.count)
            }
        }

        if !warnings.isEmpty {
            if !errors.isEmpty { Divider() }
            Section {
                ForEach(Array(warnings.enumerated()), id: \.element.id) { index, item in
                    AlertRowView(item: item, serverURL: serverURL)
                    if index < warnings.count - 1 {
                        Divider()
                    }
                }
            } header: {
                SectionHeaderView(title: "Warnings", count: warnings.count)
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeaderView: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(title.uppercased()) (\(count))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            Divider()
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .padding(.horizontal, -12)
    }
}

// MARK: - Open in PRTG

func openPrtgDashboard(serverURL: String) {
    let base = serverURL
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    guard var components = URLComponents(string: base) else { return }
    components.port = nil
    components.path = "/"
    guard let url = components.url else { return }
    NSWorkspace.shared.open(url)
}

func openInPrtg(objectId: Int, serverURL: String) {
    let base = serverURL
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    guard var components = URLComponents(string: base) else { return }
    components.port = nil
    components.path = "/sensor.htm"
    components.queryItems = [URLQueryItem(name: "id", value: "\(objectId)")]

    guard let url = components.url else { return }
    NSWorkspace.shared.open(url)
}
