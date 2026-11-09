import Foundation

struct SensorSnapshot: Equatable, Sendable {
    let id: Int
    let name: String
    let deviceId: Int
    let deviceName: String
    /// nil when the sensor hangs outside any probe, so it groups by device instead.
    let projectId: Int?
    let projectName: String
    let status: SensorStatus
    let isAcknowledged: Bool
    let message: String?
}

enum CombineMode: String, CaseIterable, Sendable {
    case never, perDevice, perProject
}

struct AlertConfig: Equatable, Sendable {
    var alertOnDown = true
    var alertOnWarning = false
    var alertOnRecovery = true
    var extraChecks = 1
    var combine: CombineMode = .perDevice
    var muteFlapping = true
    var flapThreshold = 6
    var flapWindow: TimeInterval = 900
    var flapCalm: TimeInterval = 900
    var skipAcknowledgedAndPaused = true
    var reminderInterval: TimeInterval?
    var snoozedUntil: Date?
}

enum AlertKind: Equatable, Sendable {
    case down, warning, recovery, flapping, reminder
}

struct Alert: Equatable, Sendable {
    let kind: AlertKind
    let title: String
    let body: String
    let sensorIds: [Int]
    let deviceId: Int
    let threadId: String
    let playSound: Bool
}

struct AlertEngine: Sendable {
    var config: AlertConfig
    private var states: [Int: SensorAlertState] = [:]
    private var hasBaseline = false

    init(config: AlertConfig = AlertConfig()) {
        self.config = config
    }

    mutating func process(_ snapshot: [SensorSnapshot], at now: Date) -> [Alert] {
        let isBaseline = !hasBaseline
        hasBaseline = true
        var nextStates: [Int: SensorAlertState] = [:]
        var events: [(SensorSnapshot, SensorEvent)] = []
        for sensor in snapshot {
            let observation = observe(sensor, at: now)
            guard !isBaseline, let state = states[sensor.id] else {
                nextStates[sensor.id] = .baseline(observation.effectiveClass, at: now)
                continue
            }
            let (next, event) = state.advancing(with: observation, config: config)
            nextStates[sensor.id] = next
            if let event { events.append((sensor, event)) }
        }
        states = nextStates
        if config.isSnoozed(at: now) { return [] }
        return compose(events)
    }

    private func observe(_ sensor: SensorSnapshot, at now: Date) -> SensorObservation {
        let rawClass = StatusClass(sensor.status)
        let skipped = config.skipAcknowledgedAndPaused && sensor.isAcknowledged
        return SensorObservation(effectiveClass: skipped ? .ok : rawClass, status: sensor.status,
                                 isAcknowledged: sensor.isAcknowledged, now: now)
    }

    // MARK: - Composing

    private func compose(_ events: [(SensorSnapshot, SensorEvent)]) -> [Alert] {
        let sorted = events.sorted { ($0.0.name, $0.0.id) < ($1.0.name, $1.0.id) }
        func sensors(_ matches: (SensorEvent) -> Bool) -> [SensorSnapshot] {
            sorted.filter { matches($0.1) }.map(\.0)
        }
        let grouped = groupedAlerts(.down, sensors { $0 == .problem(.down) })
            + groupedAlerts(.warning, sensors { $0 == .problem(.warning) })
            + groupedAlerts(.recovery, sensors { $0 == .recovery })
        let single = sorted.compactMap { sensor, event -> Alert? in
            switch event {
            case .flapping(let changes):
                singleAlert(.flapping, sensor, body: flappingBody(changes))
            case .reminder:
                singleAlert(.reminder, sensor, body: sensor.message ?? "")
            case .problem, .recovery:
                nil
            }
        }
        return grouped + single
    }

    private func groupedAlerts(_ kind: AlertKind, _ sensors: [SensorSnapshot]) -> [Alert] {
        var keys: [String] = []
        var groups: [String: [SensorSnapshot]] = [:]
        for sensor in sensors {
            let key = groupKey(sensor)
            if groups[key] == nil { keys.append(key) }
            groups[key, default: []].append(sensor)
        }
        return keys.compactMap { groups[$0] }.map { groupAlert(kind, $0) }
    }

    private func groupKey(_ sensor: SensorSnapshot) -> String {
        switch config.combine {
        case .never: "sensor-\(sensor.id)"
        case .perDevice: "device-\(sensor.deviceId)"
        case .perProject: sensor.projectId.map { "project-\($0)" } ?? "device-\(sensor.deviceId)"
        }
    }

    private func groupAlert(_ kind: AlertKind, _ sensors: [SensorSnapshot]) -> Alert {
        let first = sensors[0]
        let byProject = config.combine == .perProject && first.projectId != nil
        let label = byProject ? first.projectName : first.deviceName
        let threadId = byProject ? groupKey(first) : "device-\(first.deviceId)"
        let body = sensors.count > 1
            ? sensors.map(\.name).joined(separator: ", ")
            : (kind == .recovery ? "" : first.message ?? "")
        return Alert(kind: kind, title: Self.title(kind, label: label, sensors: sensors), body: body,
                     sensorIds: sensors.map(\.id), deviceId: first.deviceId, threadId: threadId,
                     playSound: kind == .down)
    }

    private func singleAlert(_ kind: AlertKind, _ sensor: SensorSnapshot, body: String) -> Alert {
        Alert(kind: kind, title: Self.title(kind, label: sensor.deviceName, sensors: [sensor]), body: body,
              sensorIds: [sensor.id], deviceId: sensor.deviceId, threadId: "device-\(sensor.deviceId)",
              playSound: kind == .reminder)
    }

    private func flappingBody(_ changes: Int) -> String {
        "\(changes) changes in \(Int(config.flapWindow / 60)) min. Muted until it settles."
    }

    private static func title(_ kind: AlertKind, label: String, sensors: [SensorSnapshot]) -> String {
        let count = sensors.count
        let name = sensors[0].name
        switch kind {
        case .down: return count == 1 ? "\(label): \(name) is down" : "\(label): \(count) sensors down"
        case .warning: return count == 1 ? "\(label): \(name) has a warning" : "\(label): \(count) warnings"
        case .recovery: return count == 1 ? "\(label): \(name) is OK again" : "\(label): \(count) sensors OK again"
        case .flapping: return "\(label): \(name) is flapping"
        case .reminder: return "Still down: \(label) \(name)"
        }
    }
}

extension SensorSnapshot {
    static func collect(in roots: [TreeNode], projectLevel: Int = 1) -> [SensorSnapshot] {
        var result: [SensorSnapshot] = []
        func walk(_ node: TreeNode, ancestors: [TreeNode]) {
            if node.kind == .sensor, let device = ancestors.last(where: { $0.kind == .device }) {
                result.append(SensorSnapshot(
                    id: node.id, name: node.name, deviceId: device.id, deviceName: device.name,
                    projectId: ProjectBuilder.projectId(ancestors: ancestors, level: projectLevel),
                    projectName: ProjectBuilder.projectName(ancestors: ancestors, level: projectLevel), status: node.status,
                    isAcknowledged: node.isAcknowledged, message: node.message
                ))
            }
            for child in node.children { walk(child, ancestors: ancestors + [node]) }
        }
        roots.forEach { walk($0, ancestors: []) }
        return result
    }
}
