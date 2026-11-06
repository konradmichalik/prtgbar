import Foundation

enum StatusClass: Int, Comparable, Sendable {
    case ok, warning, down

    init(_ status: SensorStatus) {
        switch status {
        case .down, .partialdown: self = .down
        case .warning, .unusual: self = .warning
        case .up, .paused, .unknown: self = .ok
        }
    }

    static func < (lhs: StatusClass, rhs: StatusClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum SensorEvent: Equatable, Sendable {
    case problem(StatusClass)
    case recovery
    case flapping(changes: Int)
    case reminder
}

struct SensorObservation: Sendable {
    let effectiveClass: StatusClass
    let status: SensorStatus
    let isAcknowledged: Bool
    let now: Date
}

/// A problem span runs from leaving ok-class until the sensor is ok-class again,
/// so down and warning changes inside one outage share their alerts.
struct SensorAlertState: Equatable, Sendable {
    var lastClass: StatusClass
    var streak = 1
    /// Highest class already alerted, or known at baseline, in the current span.
    var covered: StatusClass
    var alerted = false
    var changeTimes: [Date] = []
    var lastChange: Date
    var flappingSince: Date?
    /// Time of the span's down alert or its latest reminder.
    var lastReminder: Date?

    static func baseline(_ statusClass: StatusClass, at now: Date) -> SensorAlertState {
        SensorAlertState(lastClass: statusClass, covered: statusClass, lastChange: now)
    }

    func advancing(with observation: SensorObservation, config: AlertConfig) -> (SensorAlertState, SensorEvent?) {
        let changed = observation.effectiveClass != lastClass
        var next = observing(observation, config: config)
        if next.flappingSince != nil {
            guard observation.now.timeIntervalSince(next.lastChange) >= config.flapCalm else { return (next, nil) }
            next = next.settled()
        } else if config.muteFlapping, changed, next.changeTimes.count >= config.flapThreshold {
            next = next.resettingSpan()
            next.flappingSince = observation.now
            return (next, .flapping(changes: next.changeTimes.count))
        }
        if changed, observation.effectiveClass == .ok {
            let recovers = next.alerted && config.alertOnRecovery && observation.status == .up
            return (next.resettingSpan(), recovers ? .recovery : nil)
        }
        return next.alertTransition(observation, config: config)
    }

    private func observing(_ observation: SensorObservation, config: AlertConfig) -> SensorAlertState {
        var next = self
        let now = observation.now
        if observation.effectiveClass != lastClass {
            next.lastClass = observation.effectiveClass
            next.streak = 1
            next.lastChange = now
            next.changeTimes.append(now)
        } else {
            next.streak += 1
        }
        next.changeTimes = next.changeTimes.filter { now.timeIntervalSince($0) < config.flapWindow }
        return next
    }

    private func resettingSpan() -> SensorAlertState {
        var next = self
        next.covered = .ok
        next.alerted = false
        next.lastReminder = nil
        return next
    }

    /// A sensor that calms down starts a fresh span in its current class.
    private func settled() -> SensorAlertState {
        var next = resettingSpan()
        next.flappingSince = nil
        next.changeTimes = []
        next.streak = 1
        return next
    }

    private func alertTransition(_ observation: SensorObservation, config: AlertConfig) -> (SensorAlertState, SensorEvent?) {
        var next = self
        let statusClass = observation.effectiveClass
        let now = observation.now
        if statusClass > covered, streak >= config.extraChecks + 1 {
            guard config.alertsEnabled(for: statusClass) else { return (next, nil) }
            next.covered = statusClass
            next.alerted = true
            if statusClass == .down { next.lastReminder = now }
            return (next, .problem(statusClass))
        }
        guard statusClass == .down, covered == .down, alerted, !observation.isAcknowledged,
              let interval = config.reminderInterval, let last = lastReminder,
              now.timeIntervalSince(last) >= interval else {
            return (next, nil)
        }
        next.lastReminder = now
        return (next, .reminder)
    }
}

extension AlertConfig {
    func alertsEnabled(for statusClass: StatusClass) -> Bool {
        switch statusClass {
        case .down: alertOnDown
        case .warning: alertOnWarning
        case .ok: false
        }
    }
}
