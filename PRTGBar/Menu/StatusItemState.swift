import Foundation

/// What the menu bar item shows. Counts of 0 mean the count is hidden by the user's settings.
enum StatusItemState: Equatable {
    case allUp
    case warningsOnly(Int)
    case down(Int)
    case unreachable
    case snoozed(downCount: Int)

    static func make(model: MenuModel, showCount: Bool, showWarningIndicator: Bool) -> StatusItemState {
        let down = showCount ? model.summary.down : 0
        if model.errorMessage != nil { return .unreachable }
        if model.snoozedUntil != nil { return .snoozed(downCount: down) }
        if model.summary.down > 0 { return .down(down) }
        if showWarningIndicator, model.summary.warning > 0 {
            return .warningsOnly(showCount ? model.summary.warning : 0)
        }
        return .allUp
    }

    /// The gauge shows warning and down itself; only snooze needs an extra mark.
    var badgeSymbol: String? {
        if case .snoozed = self { return "bell.slash" }
        return nil
    }

    var gaugeLevel: GaugeLevel {
        switch self {
        case .allUp, .unreachable: .ok
        case .warningsOnly: .warning
        case .down: .down
        case .snoozed(let downCount): downCount > 0 ? .down : .ok
        }
    }

    var countText: String {
        switch self {
        case .warningsOnly(let count), .down(let count), .snoozed(let count):
            count > 0 ? "\(count)" : ""
        case .allUp, .unreachable:
            ""
        }
    }
}
