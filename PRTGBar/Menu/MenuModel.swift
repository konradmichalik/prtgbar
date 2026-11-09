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

    struct Input {
        var roots: [TreeNode] = []
        var timestamps: [Int: Date] = [:]
        var sort: ProblemSort = .newestFirst
        /// Which group level counts as a project, see `ProjectBuilder`.
        var projectLevel = 1
        var serverURL = ""
        /// Only whether a key exists; the key itself never enters the model.
        var hasAPIKey = false
        var lastUpdated: Date?
        var error: String?
        var actionError: String?
        var snoozedUntil: Date?
        var showHistory = true
    }

    static func make(_ input: Input) -> MenuModel {
        MenuModel(
            serverHost: host(of: input.serverURL),
            summary: summary(of: input.roots),
            problems: ProblemList.make(
                from: input.roots, timestamps: input.timestamps, sort: input.sort, projectLevel: input.projectLevel
            ),
            projects: ProjectBuilder.projects(from: input.roots, level: input.projectLevel),
            lastUpdated: input.lastUpdated,
            errorMessage: input.error,
            actionError: input.actionError,
            snoozedUntil: input.snoozedUntil,
            isConfigured: !input.serverURL.isEmpty && input.hasAPIKey,
            showHistory: input.showHistory
        )
    }

    // MARK: - Private

    private static func host(of serverURL: String) -> String {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.host ?? trimmed
    }

    private static func summary(of roots: [TreeNode]) -> StatusSummary {
        var counts = (up: 0, down: 0, warning: 0, paused: 0, unknown: 0, unusual: 0)
        func visit(_ node: TreeNode) {
            if node.kind == .sensor {
                switch node.status {
                case .up: counts.up += 1
                case .paused: counts.paused += 1
                case .down, .partialdown, .warning, .unusual:
                    guard !node.isAcknowledged else { return }
                    if node.status.isDownClass {
                        counts.down += 1
                    } else if node.status == .unusual {
                        counts.unusual += 1
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
                             paused: counts.paused, unknown: counts.unknown, unusual: counts.unusual)
    }
}
