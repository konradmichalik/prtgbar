import Foundation

enum SettingsMigration {
    static let version = 2
    static let allowedIntervals: [Double] = [30, 60, 120, 300]

    static func run(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: "settingsVersion") < version else { return }

        // The removed master toggle must not turn alerts back on for someone who had them off.
        if defaults.object(forKey: "notifyOnStatusChange") as? Bool == false {
            for key in ["notifyOnDown", "notifyOnWarning", "notifyOnRecovery"] {
                defaults.set(false, forKey: key)
            }
        }
        if let interval = defaults.object(forKey: "refreshInterval") as? Double {
            defaults.set(snapped(interval), forKey: "refreshInterval")
        }
        for key in ["notifyOnStatusChange", "showAllProbes", "showAcknowledged"] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(version, forKey: "settingsVersion")
    }

    static func snapped(_ interval: Double) -> Double {
        allowedIntervals.min { abs($0 - interval) < abs($1 - interval) } ?? 60
    }
}
