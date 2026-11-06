import Foundation

enum ProblemSort: String, CaseIterable {
    case newestFirst, longestFirst, byDevice
}

struct PausedDeviceLine: Equatable {
    let deviceId: Int
    let heading: String
    let pausedCount: Int
}

enum AcknowledgedEntry {
    case sensor(ProblemItem)
    case pausedDevice(PausedDeviceLine)
}

struct ProblemList {
    let down: [ProblemItem]
    let warning: [ProblemItem]
    let acknowledged: [ProblemItem]
    let paused: [PausedDeviceLine]

    static func make(from roots: [TreeNode], timestamps: [Int: Date], sort: ProblemSort) -> ProblemList {
        let items = ProblemItem.collect(from: roots, fallbackTimestamps: timestamps)
        let open = items.filter { !$0.isAcknowledged }
        return ProblemList(
            down: sorted(open.filter { $0.status == .down || $0.status == .partialdown }, by: sort),
            warning: sorted(open.filter { $0.status == .warning || $0.status == .unusual }, by: sort),
            acknowledged: sorted(items.filter(\.isAcknowledged), by: sort),
            paused: pausedLines(from: roots)
        )
    }

    func cappedEntries(limit: Int) -> (entries: [AcknowledgedEntry], remaining: Int) {
        let all = acknowledged.map(AcknowledgedEntry.sensor) + paused.map(AcknowledgedEntry.pausedDevice)
        return (Array(all.prefix(limit)), max(all.count - limit, 0))
    }

    // MARK: - Private

    private static func sorted(_ items: [ProblemItem], by sort: ProblemSort) -> [ProblemItem] {
        items.sorted { a, b in
            switch sort {
            case .newestFirst: byDate(a, b, newerFirst: true)
            case .longestFirst: byDate(a, b, newerFirst: false)
            case .byDevice:
                if a.deviceName != b.deviceName {
                    a.deviceName.localizedCaseInsensitiveCompare(b.deviceName) == .orderedAscending
                } else {
                    a.sensorName.localizedCaseInsensitiveCompare(b.sensorName) == .orderedAscending
                }
            }
        }
    }

    /// Items without a date always go last, ordered by sensor name.
    private static func byDate(_ a: ProblemItem, _ b: ProblemItem, newerFirst: Bool) -> Bool {
        switch (a.downSince, b.downSince) {
        case (let da?, let db?): da != db ? (newerFirst ? da > db : da < db) : a.sensorName < b.sensorName
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): a.sensorName < b.sensorName
        }
    }

    private static func pausedLines(from roots: [TreeNode]) -> [PausedDeviceLine] {
        var lines: [PausedDeviceLine] = []
        for root in roots {
            collectPaused(root, ancestors: [], into: &lines)
        }
        return lines.sorted { $0.heading.localizedCaseInsensitiveCompare($1.heading) == .orderedAscending }
    }

    private static func collectPaused(_ node: TreeNode, ancestors: [TreeNode], into lines: inout [PausedDeviceLine]) {
        if node.kind == .device {
            let count = node.children.filter { $0.kind == .sensor && $0.status == .paused }.count
            if count > 0 {
                lines.append(PausedDeviceLine(
                    deviceId: node.id,
                    heading: ProjectBuilder.heading(
                        path: ProjectBuilder.subgroupPath(ancestors: ancestors),
                        deviceName: node.name
                    ),
                    pausedCount: count
                ))
            }
            return
        }
        for child in node.children {
            collectPaused(child, ancestors: ancestors + [node], into: &lines)
        }
    }
}
