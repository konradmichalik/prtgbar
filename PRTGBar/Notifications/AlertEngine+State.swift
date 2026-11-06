import Foundation

enum StatusClass: Equatable, Sendable {
    case ok, warning, down

    init(_ status: SensorStatus) {
        switch status {
        case .down, .partialdown: self = .down
        case .warning, .unusual: self = .warning
        case .up, .paused, .unknown: self = .ok
        }
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
    let rawClass: StatusClass
    let isAcknowledged: Bool
    let now: Date
}

struct SensorAlertState: Equatable, Sendable {
    var lastClass: StatusClass
    var streak = 1
    var alerted = false
    /// Episodes already in progress at baseline or when flapping settles never alert.
    var known: Bool
    var changeTimes: [Date] = []
    var lastChange: Date
    var flappingSince: Date?
    /// Time of the episode's alert or its latest reminder.
    var lastReminder: Date?

    static func baseline(_ statusClass: StatusClass, at now: Date) -> SensorAlertState {
        SensorAlertState(lastClass: statusClass, known: statusClass != .ok, lastChange: now)
    }

    func advancing(with observation: SensorObservation, config: AlertConfig) -> (SensorAlertState, SensorEvent?) {
        let changed = observation.effectiveClass != lastClass
        let observed = observing(observation, config: config)
        if let flapResult = observed.flapTransition(changed: changed, now: observation.now, config: config) {
            return flapResult
        }
        if changed, alerted, observation.effectiveClass == .ok {
            let recovers = config.alertOnRecovery && observation.rawClass == .ok
            return (observed, recovers ? .recovery : nil)
        }
        return observed.alertTransition(observation, config: config)
    }

    private func observing(_ observation: SensorObservation, config: AlertConfig) -> SensorAlertState {
        var next = self
        let now = observation.now
        if observation.effectiveClass != lastClass {
            next.lastClass = observation.effectiveClass
            next.streak = 1
            next.alerted = false
            next.known = false
            next.lastChange = now
            next.lastReminder = nil
            next.changeTimes.append(now)
        } else {
            next.streak += 1
        }
        next.changeTimes = next.changeTimes.filter { now.timeIntervalSince($0) < config.flapWindow }
        return next
    }

    /// Returns nil when flapping does not apply and normal alerting continues.
    private func flapTransition(changed: Bool, now: Date, config: AlertConfig) -> (SensorAlertState, SensorEvent?)? {
        var next = self
        if flappingSince != nil {
            if now.timeIntervalSince(lastChange) >= config.flapCalm {
                next.flappingSince = nil
                next.changeTimes = []
                next.known = lastClass != .ok
            }
            return (next, nil)
        }
        guard config.muteFlapping, changed, changeTimes.count >= config.flapThreshold else { return nil }
        next.flappingSince = now
        return (next, .flapping(changes: changeTimes.count))
    }

    private func alertTransition(_ observation: SensorObservation, config: AlertConfig) -> (SensorAlertState, SensorEvent?) {
        var next = self
        let statusClass = observation.effectiveClass
        let now = observation.now
        if statusClass != .ok, !known, !alerted, streak >= config.extraChecks + 1 {
            guard config.alertsEnabled(for: statusClass) else { return (next, nil) }
            next.alerted = true
            next.lastReminder = now
            return (next, .problem(statusClass))
        }
        guard statusClass == .down, alerted, !observation.isAcknowledged,
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
