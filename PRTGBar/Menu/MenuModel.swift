import Foundation

struct MenuModel {
    let serverHost: String
    let summary: StatusSummary
    let problems: ProblemList
    let projects: [Project]
    let lastUpdated: Date?
    let errorMessage: String?
    /// A failed acknowledge or pause; unlike `errorMessage` it says nothing about reachability.
    let actionError: String?
    let snoozedUntil: Date?
    let isConfigured: Bool
    let showHistory: Bool

    static func make(
        roots: [TreeNode],
        timestamps: [Int: Date],
        sort: ProblemSort,
        serverURL: String,
        lastUpdated: Date?,
        error: String?,
        actionError: String? = nil,
        snoozedUntil: Date?,
        showHistory: Bool = true
    ) -> MenuModel {
        MenuModel(
            serverHost: host(of: serverURL),
            summary: summary(of: roots),
            problems: ProblemList.make(from: roots, timestamps: timestamps, sort: sort),
            projects: ProjectBuilder.projects(from: roots),
            lastUpdated: lastUpdated,
            errorMessage: error,
            actionError: actionError,
            snoozedUntil: snoozedUntil,
            isConfigured: !serverURL.isEmpty,
            showHistory: showHistory
        )
    }

    // MARK: - Private

    private static func host(of serverURL: String) -> String {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host ?? trimmed
    }

    private static func summary(of roots: [TreeNode]) -> StatusSummary {
        var counts = (up: 0, down: 0, warning: 0, paused: 0, unknown: 0)
        func visit(_ node: TreeNode) {
            if node.kind == .sensor {
                switch node.status {
                case .up: counts.up += 1
                case .paused: counts.paused += 1
                case .down, .partialdown, .warning, .unusual:
                    guard !SensorMessage(node.message ?? "").isAcknowledged else { return }
                    if node.status == .down || node.status == .partialdown {
                        counts.down += 1
                    } else {
                        counts.warning += 1
                    }
                case .unknown: counts.unknown += 1
                }
            }
            node.children.forEach(visit)
        }
        roots.forEach(visit)
        return StatusSummary(up: counts.up, down: counts.down, warning: counts.warning,
                             paused: counts.paused, unknown: counts.unknown)
    }
}
