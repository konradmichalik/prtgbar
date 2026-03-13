import Foundation

// MARK: - Status Pill Filter

enum StatusPillFilter: Equatable {
    case up, down, warning, paused

    var statuses: Set<SensorStatus> {
        switch self {
        case .up: [.up]
        case .down: [.down, .partialdown]
        case .warning: [.warning, .unusual]
        case .paused: [.paused]
        }
    }
}

// MARK: - Tree Filtering

enum TreeFilter {
    static func filter(_ nodes: [TreeNode], query: String, statusFilter: StatusPillFilter? = nil) -> [TreeNode] {
        var result = nodes

        if !query.isEmpty {
            let lowered = query.lowercased()
            result = result.compactMap { filterByQuery($0, query: lowered) }
        }

        if let statusFilter {
            result = result.compactMap { filterByStatus($0, statuses: statusFilter.statuses) }
        }

        return result
    }

    private static func filterByQuery(_ node: TreeNode, query: String) -> TreeNode? {
        let nameMatches = node.name.lowercased().contains(query)
        let messageMatches = node.message?.lowercased().contains(query) ?? false
        let selfMatches = nameMatches || messageMatches

        let filteredChildren = node.children.compactMap { filterByQuery($0, query: query) }

        if selfMatches || !filteredChildren.isEmpty {
            return TreeNode(
                id: node.id,
                name: node.name,
                kind: node.kind,
                status: node.status,
                message: node.message,
                statusSummary: node.statusSummary,
                lastDown: node.lastDown,
                children: selfMatches ? node.children : filteredChildren
            )
        }

        return nil
    }

    private static func filterByStatus(_ node: TreeNode, statuses: Set<SensorStatus>) -> TreeNode? {
        if node.kind == .sensor {
            return statuses.contains(node.status) ? node : nil
        }

        let filteredChildren = node.children.compactMap { filterByStatus($0, statuses: statuses) }

        guard !filteredChildren.isEmpty else { return nil }

        return TreeNode(
            id: node.id,
            name: node.name,
            kind: node.kind,
            status: node.status,
            message: node.message,
            statusSummary: node.statusSummary,
            lastDown: node.lastDown,
            children: filteredChildren
        )
    }
}
