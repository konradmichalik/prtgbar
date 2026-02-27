import SwiftUI

// MARK: - Sensor Message Parsing

struct SensorMessage {
    let isAcknowledged: Bool
    let text: String

    init(_ raw: String) {
        let prefixes = ["Bestätigt von ", "Acknowledged by "]
        guard prefixes.contains(where: { raw.hasPrefix($0) }) else {
            isAcknowledged = false
            text = raw
            return
        }
        isAcknowledged = true
        if let range = raw.range(of: "]: ") {
            text = String(raw[range.upperBound...])
        } else if let range = raw.range(of: ": ", options: .backwards) {
            text = String(raw[range.upperBound...])
        } else {
            text = raw
        }
    }
}

// MARK: - Sensor Status

enum SensorStatus: String, Codable, CaseIterable {
    case up
    case down
    case warning
    case paused
    case unusual
    case partialdown
    case unknown

    var symbolName: String {
        switch self {
        case .up: "checkmark.circle.fill"
        case .down: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        case .unusual: "exclamationmark.circle.fill"
        case .partialdown: "exclamationmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .up: .green
        case .down: .red
        case .warning: .yellow
        case .paused: .secondary
        case .unusual: .orange
        case .partialdown: .orange
        case .unknown: .secondary
        }
    }

    static let problemStatuses: Set<SensorStatus> = [.down, .partialdown, .warning, .unusual]

    var severity: Int {
        switch self {
        case .down: 0
        case .partialdown: 1
        case .warning: 2
        case .unusual: 3
        case .unknown: 4
        case .paused: 5
        case .up: 6
        }
    }
}

// MARK: - Status Summary

struct StatusSummary: Codable, Equatable {
    let up: Int
    let down: Int
    let warning: Int
    let paused: Int
    let unknown: Int

    var total: Int { up + down + warning + paused + unknown }

    static let empty = StatusSummary(up: 0, down: 0, warning: 0, paused: 0, unknown: 0)
}

// MARK: - PRTG Object (API Response)

enum ObjectKind: String, Codable {
    case probedevice
    case group
    case device
    case sensor
}

struct ParentRef: Codable, Equatable {
    let id: Int
    let type: String
    let name: String
}

struct PrtgObject: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let kind: ObjectKind
    let status: SensorStatus?
    let message: String?
    let parent: ParentRef?
    let tags: [String]?
    let active: Bool?
    let sensorStatusSummary: StatusSummary?
    let lastDown: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, status, message, parent, tags, active, lastDown
        case sensorStatusSummary = "sensor_status_summary"
    }
}

struct PrtgObjectsResponse: Codable {
    let items: [PrtgObject]

    enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        // The API may return items at the top level as an array or inside an "items" key
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            items = (try? container.decode([PrtgObject].self, forKey: .items)) ?? []
        } else {
            items = (try? decoder.singleValueContainer().decode([PrtgObject].self)) ?? []
        }
    }
}

// MARK: - Tree Node

final class TreeNode: Identifiable, Equatable, @unchecked Sendable {
    let id: Int
    let name: String
    let kind: ObjectKind
    let status: SensorStatus
    let message: String?
    let statusSummary: StatusSummary?
    let lastDown: Date?
    var children: [TreeNode]

    var hasDownSensors: Bool {
        if status == .down { return true }
        if let summary = statusSummary, summary.down > 0 { return true }
        return children.contains { $0.hasDownSensors }
    }

    var worstStatus: SensorStatus {
        let childWorst = children.map(\.worstStatus).min(by: { $0.severity < $1.severity })
        if let childWorst, childWorst.severity < status.severity {
            return childWorst
        }
        return status
    }

    var totalSensorCount: Int {
        if kind == .sensor { return 1 }
        if let summary = statusSummary { return summary.total }
        return children.reduce(0) { $0 + $1.totalSensorCount }
    }

    init(
        id: Int,
        name: String,
        kind: ObjectKind,
        status: SensorStatus,
        message: String? = nil,
        statusSummary: StatusSummary? = nil,
        lastDown: Date? = nil,
        children: [TreeNode] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.message = message
        self.statusSummary = statusSummary
        self.lastDown = lastDown
        self.children = children
    }

    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Problem Item

struct ProblemItem: Identifiable {
    let id: Int
    let sensorName: String
    let status: SensorStatus
    let message: String?
    let deviceName: String
    let groupName: String?
    let downSince: Date?

    var breadcrumb: String {
        if let groupName, !deviceName.isEmpty {
            return "\(groupName) › \(deviceName)"
        }
        return deviceName.isEmpty ? (groupName ?? "") : deviceName
    }

    static func collect(from nodes: [TreeNode], fallbackTimestamps: [Int: Date] = [:]) -> [ProblemItem] {
        var items: [ProblemItem] = []
        for node in nodes {
            walk(node, ancestors: [], fallbackTimestamps: fallbackTimestamps, into: &items)
        }
        return items.sorted { $0.status.severity < $1.status.severity }
    }

    private static func walk(
        _ node: TreeNode,
        ancestors: [TreeNode],
        fallbackTimestamps: [Int: Date],
        into items: inout [ProblemItem]
    ) {
        if node.kind == .sensor, node.status != .up, node.status != .paused {
            let device = ancestors.last { $0.kind == .device }
            let group = ancestors.last { $0.kind == .group }
            items.append(ProblemItem(
                id: node.id,
                sensorName: node.name,
                status: node.status,
                message: node.message,
                deviceName: device?.name ?? "",
                groupName: group?.name,
                downSince: node.lastDown ?? fallbackTimestamps[node.id]
            ))
        }
        for child in node.children {
            walk(child, ancestors: ancestors + [node], fallbackTimestamps: fallbackTimestamps, into: &items)
        }
    }
}

// MARK: - Tree Building

enum TreeBuilder {
    static func buildTree(from objects: [PrtgObject]) -> [TreeNode] {
        let nodes = objects.map { obj in
            TreeNode(
                id: obj.id,
                name: obj.name,
                kind: obj.kind,
                status: obj.status ?? .unknown,
                message: obj.message,
                statusSummary: obj.sensorStatusSummary,
                lastDown: obj.lastDown
            )
        }

        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        var roots: [TreeNode] = []

        for (index, obj) in objects.enumerated() {
            let node = nodes[index]
            if let parentId = obj.parent?.id, let parentNode = nodeMap[parentId] {
                parentNode.children.append(node)
            } else {
                roots.append(node)
            }
        }

        sortChildren(roots)
        return roots
    }

    private static func sortChildren(_ nodes: [TreeNode]) {
        for node in nodes {
            node.children.sort { a, b in
                if a.kind != b.kind {
                    return kindOrder(a.kind) < kindOrder(b.kind)
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            sortChildren(node.children)
        }
    }

    private static func kindOrder(_ kind: ObjectKind) -> Int {
        switch kind {
        case .probedevice: 0
        case .group: 1
        case .device: 2
        case .sensor: 3
        }
    }
}
