import Foundation

// MARK: - Project Device

struct ProjectDevice: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Subgroup names between the project and the device.
    let path: [String]
    let problemSensors: [TreeNode]
    let upCount: Int
    let pausedCount: Int
    let acknowledgedCount: Int

    var heading: String {
        ProjectBuilder.heading(path: path, deviceName: name)
    }

    var quietSummary: String {
        switch (problemSensors.isEmpty, pausedCount > 0) {
        case (true, false): upCount == 1 ? "All 1 sensor up" : "All \(upCount) sensors up"
        case (true, true): "\(upCount) up, \(pausedCount) paused"
        case (false, true): "\(upCount) more up, \(pausedCount) paused"
        case (false, false): "\(upCount) more up"
        }
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
    let sensorCount: Int
    var displayName: String
    var worstStatus: SensorStatus
}

// MARK: - Project Building

enum ProjectBuilder {
    /// Name of the group directly below a probe in the ancestor chain (root first),
    /// or the probe name when the node hangs directly under the probe.
    static func projectName(ancestors: [TreeNode]) -> String {
        if let index = projectGroupIndex(ancestors: ancestors) {
            return ancestors[index].name
        }
        return ancestors.last { $0.kind == .probedevice }?.name ?? ""
    }

    /// Group names between the project group and the device, root first.
    static func subgroupPath(ancestors: [TreeNode]) -> [String] {
        projectGroupIndex(ancestors: ancestors)
            .map { ancestors[($0 + 1)...].filter { $0.kind == .group }.map(\.name) } ?? []
    }

    static func heading(path: [String], deviceName: String) -> String {
        (path + [deviceName]).joined(separator: " › ")
    }

    static func projects(from roots: [TreeNode]) -> [Project] {
        var buckets: [Bucket] = []
        for root in roots {
            collect(root, ancestors: [], into: &buckets)
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
        var sensorCount = 0
        var worstStatus: SensorStatus = .up
    }

    private static func projectGroupIndex(ancestors: [TreeNode]) -> Int? {
        ancestors.indices.dropFirst().first {
            ancestors[$0].kind == .group && ancestors[$0 - 1].kind == .probedevice
        }
    }

    private static func collect(_ node: TreeNode, ancestors: [TreeNode], into buckets: inout [Bucket]) {
        if node.kind == .device {
            add(device: node, ancestors: ancestors, into: &buckets)
            return
        }
        for child in node.children {
            collect(child, ancestors: ancestors + [node], into: &buckets)
        }
    }

    private static func add(device node: TreeNode, ancestors: [TreeNode], into buckets: inout [Bucket]) {
        guard let probe = ancestors.last(where: { $0.kind == .probedevice }) else { return }
        let groupIndex = projectGroupIndex(ancestors: ancestors)
        let id = groupIndex.map { ancestors[$0].id } ?? probe.id
        let path = subgroupPath(ancestors: ancestors)

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
            upCount: sensors.filter { $0.status == .up }.count,
            pausedCount: sensors.filter { $0.status == .paused }.count,
            acknowledgedCount: sensors.filter(isAcknowledgedProblem).count
        )

        var bucket = buckets.first { $0.id == id }
            ?? Bucket(id: id, name: projectName(ancestors: ancestors), probeName: probe.name)
        bucket.devices.append(projectDevice)
        bucket.sensorCount += sensors.count
        bucket.downCount += problems.filter { $0.status == .down || $0.status == .partialdown }.count
        bucket.warningCount += problems.filter { $0.status == .warning || $0.status == .unusual }.count
        if let worst = problems.first, worst.status.severity < bucket.worstStatus.severity {
            bucket.worstStatus = worst.status
        }
        if let index = buckets.firstIndex(where: { $0.id == id }) {
            buckets[index] = bucket
        } else {
            buckets.append(bucket)
        }
    }

    private static func isAcknowledgedProblem(_ sensor: TreeNode) -> Bool {
        SensorStatus.problemStatuses.contains(sensor.status)
            && SensorMessage(sensor.message ?? "").isAcknowledged
    }

    private static func isProblem(_ sensor: TreeNode) -> Bool {
        SensorStatus.problemStatuses.contains(sensor.status) && !isAcknowledgedProblem(sensor)
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
            sensorCount: bucket.sensorCount,
            displayName: bucket.name,
            worstStatus: bucket.worstStatus
        )
    }

    private static func applyDisplayNames(to projects: [Project]) -> [Project] {
        let nameCounts = Dictionary(grouping: projects, by: \.name).mapValues(\.count)
        return projects.map { project in
            guard nameCounts[project.name, default: 0] > 1 else { return project }
            var renamed = project
            renamed.displayName = "\(project.name) · \(project.probeName)"
            return renamed
        }
    }
}
