import Foundation

// MARK: - Project Device

struct ProjectDevice: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Subgroup names between the project and the device.
    let path: [String]
    let problemSensors: [TreeNode]
    /// Every sensor of the device, sorted by name.
    let sensors: [TreeNode]
    let upCount: Int
    let pausedCount: Int

    var heading: String {
        ProjectBuilder.heading(path: path, deviceName: name)
    }
}

// MARK: - Project

struct Project: Identifiable, Equatable {
    let id: Int
    let name: String
    let probeName: String
    let devices: [ProjectDevice]
    let downCount: Int
    let warningCount: Int
    let unusualCount: Int
    let sensorCount: Int
    var displayName: String
    var worstStatus: SensorStatus
}

// MARK: - Project Building

enum ProjectBuilder {
    /// Name of the project group in the ancestor chain (root first), or the probe name
    /// when the node hangs directly under the probe. `level` counts groups from the top, the probe excluded.
    static func projectName(ancestors: [TreeNode], level: Int = 1) -> String {
        projectNode(ancestors: ancestors, level: level)?.name ?? ""
    }

    /// Names repeat across probes, so grouping goes by this id.
    static func projectId(ancestors: [TreeNode], level: Int = 1) -> Int? {
        projectNode(ancestors: ancestors, level: level)?.id
    }

    /// Group names between the project group and the device, root first.
    static func subgroupPath(ancestors: [TreeNode], level: Int = 1) -> [String] {
        projectGroupIndex(ancestors: ancestors, level: level)
            .map { ancestors[($0 + 1)...].filter { $0.kind == .group }.map(\.name) } ?? []
    }

    static func heading(path: [String], deviceName: String) -> String {
        (path + [deviceName]).joined(separator: " › ")
    }

    static func projects(from roots: [TreeNode], level: Int = 1) -> [Project] {
        var buckets: [Bucket] = []
        for root in roots {
            collect(root, ancestors: [], level: level, into: &buckets)
        }
        let projects = buckets.map(makeProject).sorted { a, b in
            if a.worstStatus.severity != b.worstStatus.severity {
                return a.worstStatus.severity < b.worstStatus.severity
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return applyDisplayNames(to: projects)
    }

    // MARK: - Private

    private struct Bucket {
        let id: Int
        let name: String
        let probeName: String
        var devices: [ProjectDevice] = []
        var downCount = 0
        var warningCount = 0
        var unusualCount = 0
        var sensorCount = 0
        var worstStatus: SensorStatus = .up
    }

    private static func projectNode(ancestors: [TreeNode], level: Int) -> TreeNode? {
        if let index = projectGroupIndex(ancestors: ancestors, level: level) {
            return ancestors[index]
        }
        return ancestors.last { $0.kind == .probedevice }
    }

    /// The group at `level`, or the deepest group when the device sits higher up.
    /// Counting groups instead of looking for the probe keeps projects working when no probe was loaded.
    private static func projectGroupIndex(ancestors: [TreeNode], level: Int) -> Int? {
        let groupIndices = ancestors.indices.filter { ancestors[$0].kind == .group }
        guard !groupIndices.isEmpty else { return nil }
        return groupIndices[min(max(level, 1), groupIndices.count) - 1]
    }

    private static func collect(_ node: TreeNode, ancestors: [TreeNode], level: Int, into buckets: inout [Bucket]) {
        if node.kind == .device {
            add(device: node, ancestors: ancestors, level: level, into: &buckets)
            return
        }
        for child in node.children {
            collect(child, ancestors: ancestors + [node], level: level, into: &buckets)
        }
    }

    private static func add(device node: TreeNode, ancestors: [TreeNode], level: Int, into buckets: inout [Bucket]) {
        guard let id = projectId(ancestors: ancestors, level: level) else { return }
        let probeName = ancestors.last { $0.kind == .probedevice }?.name ?? ""
        let path = subgroupPath(ancestors: ancestors, level: level)

        let sensors = node.children.filter { $0.kind == .sensor }
        let problems = sensors.filter(isProblem).sorted { a, b in
            if a.status.severity != b.status.severity { return a.status.severity < b.status.severity }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        let projectDevice = ProjectDevice(
            id: node.id,
            name: node.name,
            path: path,
            problemSensors: problems,
            sensors: sensors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            upCount: sensors.filter { $0.status == .up }.count,
            pausedCount: sensors.filter { $0.status == .paused }.count
        )

        var bucket = buckets.first { $0.id == id }
            ?? Bucket(id: id, name: projectName(ancestors: ancestors, level: level), probeName: probeName)
        bucket.devices.append(projectDevice)
        bucket.sensorCount += sensors.count
        bucket.downCount += problems.filter(\.status.isDownClass).count
        bucket.warningCount += problems.filter { $0.status == .warning }.count
        bucket.unusualCount += problems.filter { $0.status == .unusual }.count
        if let worst = problems.first, worst.status.severity < bucket.worstStatus.severity {
            bucket.worstStatus = worst.status
        }
        if let index = buckets.firstIndex(where: { $0.id == id }) {
            buckets[index] = bucket
        } else {
            buckets.append(bucket)
        }
    }

    private static func isProblem(_ sensor: TreeNode) -> Bool {
        SensorStatus.problemStatuses.contains(sensor.status) && !sensor.isAcknowledged
    }

    private static func makeProject(_ bucket: Bucket) -> Project {
        let devices = bucket.devices.sorted { a, b in
            if a.problemSensors.isEmpty != b.problemSensors.isEmpty {
                return !a.problemSensors.isEmpty
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return Project(
            id: bucket.id,
            name: bucket.name,
            probeName: bucket.probeName,
            devices: devices,
            downCount: bucket.downCount,
            warningCount: bucket.warningCount,
            unusualCount: bucket.unusualCount,
            sensorCount: bucket.sensorCount,
            displayName: bucket.name,
            worstStatus: bucket.worstStatus
        )
    }

    private static func applyDisplayNames(to projects: [Project]) -> [Project] {
        let nameCounts = Dictionary(grouping: projects, by: \.name).mapValues(\.count)
        return projects.map { project in
            guard nameCounts[project.name, default: 0] > 1, !project.probeName.isEmpty else { return project }
            var renamed = project
            renamed.displayName = "\(project.name) · \(project.probeName)"
            return renamed
        }
    }
}
