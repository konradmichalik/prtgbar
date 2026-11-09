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

    /// A hidden down count still needs a mark, or down would look exactly like all up.
    var badgeSymbol: String? {
        switch self {
        case .warningsOnly: "exclamationmark.triangle.fill"
        case .down(let count): count > 0 ? nil : "xmark.circle.fill"
        case .snoozed: "bell.slash"
        case .allUp, .unreachable: nil
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
