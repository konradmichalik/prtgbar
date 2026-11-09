import AppKit
import SwiftUI

@MainActor
protocol MenuActions: AnyObject {
    func openPRTG()
    func refresh()
    func openSettings()
    func quit()
    func open(objectId: Int)
    func acknowledge(sensorIds: [Int])
    func pause(objectId: Int, minutes: Int?)
    func copy(_ text: String)
    func snooze(until: Date?)
}

// MARK: - Closure Item

/// NSMenuItem targets are weak and need an Objective-C selector, so each item carries its own handler.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(ClosureMenuItem.fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}

// MARK: - Lazy Menu

/// Builds its items on first open, so a large tree does not pay for every submenu on each open.
@MainActor
final class LazyMenu: NSMenu, NSMenuDelegate {
    private var populate: (@MainActor () -> [NSMenuItem])?

    init(_ populate: @escaping @MainActor () -> [NSMenuItem]) {
        self.populate = populate
        super.init(title: "")
        autoenablesItems = false
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let populate else { return }
        self.populate = nil
        items = populate()
    }
}

// MARK: - Builder

@MainActor
enum MenuBuilder {
    static func build(
        _ model: MenuModel,
        history: @escaping (Int) -> HistorySummary?,
        actions: MenuActions,
        activity: RefreshActivity = RefreshActivity(),
        now: Date = Date()
    ) -> NSMenu {
        let context = Context(model: model, history: history, actions: actions, activity: activity, now: now)
        return makeMenu(context.mainItems())
    }

    static func makeMenu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.items = items
        return menu
    }

    struct SensorRow {
        let id: Int
        let name: String
        let status: SensorStatus
        let message: String?
        let deviceName: String
        let breadcrumb: String
        let since: Date?
        let isAcknowledged: Bool
        var lastValue: String?
    }

    @MainActor
    struct Context {
        let model: MenuModel
        let history: (Int) -> HistorySummary?
        weak var actions: MenuActions?
        let now: Date
        let problemsById: [Int: ProblemItem]
        let devicesById: [Int: (project: Project, device: ProjectDevice)]
        /// One right-aligned column for durations and counts, so they line up across rows.
        let trailingColumn: CGFloat
        let activity: RefreshActivity

        init(
            model: MenuModel, history: @escaping (Int) -> HistorySummary?, actions: MenuActions,
            activity: RefreshActivity, now: Date
        ) {
            self.model = model
            self.activity = activity
            self.history = history
            self.actions = actions
            self.now = now
            let problems = model.problems.down + model.problems.warning + model.problems.acknowledged
            problemsById = Dictionary(problems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let leading = problems.map { MenuText.truncated($0.sensorName, max: 40) }
                + model.projects.map { "\(MenuText.truncated($0.name, max: 40))  · \(MenuText.truncated($0.probeName, max: 24))" }
            trailingColumn = Self.column(fitting: leading)
            devicesById = Dictionary(
                model.projects.flatMap { project in project.devices.map { ($0.id, (project, $0)) } },
                uniquingKeysWith: { first, _ in first }
            )
        }

        func action(_ title: String, key: String = "", _ perform: @escaping @MainActor (MenuActions) -> Void) -> NSMenuItem {
            let target = actions
            return ClosureMenuItem(title: title, keyEquivalent: key) { [weak target] in
                if let target { perform(target) }
            }
        }
    }
}

// MARK: - Main Menu

extension MenuBuilder.Context {
    func mainItems() -> [NSMenuItem] {
        guard model.isConfigured else {
            return [action("Set up PRTG…") { $0.openSettings() }, .separator()] + appItems()
        }
        let target = actions
        let summary = SummaryHeaderView(
            host: model.serverHost, summary: model.summary, hasData: model.lastUpdated != nil, activity: activity,
            openServer: { [weak target] in target?.openPRTG() }
        )
        var items: [NSMenuItem] = errorItems()
        items.append(headerItem(summary, stretches: true))
        items.append(NSMenuItem.separator())
        let problems = problemItems()
        let acknowledged = acknowledgedItems()
        items.append(contentsOf: problems)
        if !problems.isEmpty, !acknowledged.isEmpty { items.append(NSMenuItem.separator()) }
        items.append(contentsOf: acknowledged)
        items.append(contentsOf: projectSection())
        items.append(NSMenuItem.separator())
        items.append(contentsOf: prtgItems())
        items.append(NSMenuItem.separator())
        items.append(snoozeItem())
        items.append(contentsOf: appItems())
        return items
    }

    /// A stretching view follows the menu width, so content can sit at the right edge.
    func headerItem<V: View>(_ view: V, stretches: Bool = false) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
        if stretches { hosting.autoresizingMask = [.width] }
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    func sensorItem(_ row: MenuBuilder.SensorRow, showDevice: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: row.name, action: nil, keyEquivalent: "")
        item.attributedTitle = Self.rowTitle(
            MenuText.truncated(row.name, max: 40),
            secondary: showDevice && !row.deviceName.isEmpty ? MenuText.truncated(row.deviceName, max: 24) : nil,
            trailing: (row.since.map { formatDuration(now.timeIntervalSince($0)) } ?? row.lastValue).map(MenuText.muted),
            column: trailingColumn
        )
        item.image = (row.isAcknowledged ? MenuGlyph.acknowledged : MenuGlyph(status: row.status)).image
        item.submenu = LazyMenu { sensorDetailItems(row) }
        return item
    }

    func row(_ item: ProblemItem) -> MenuBuilder.SensorRow {
        MenuBuilder.SensorRow(
            id: item.id,
            name: item.sensorName,
            status: item.status,
            message: item.message.map { SensorMessage($0).text },
            deviceName: item.deviceName,
            breadcrumb: breadcrumb(for: item),
            since: item.downSince,
            isAcknowledged: item.isAcknowledged
        )
    }

    static let trailingGap: CGFloat = 60

    static func column(fitting texts: [String]) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let widest = texts.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }.max() ?? 0
        return max(MenuLayout.headerWidth - 50, widest + trailingGap)
    }

    static func rowTitle(
        _ primary: String, secondary: String? = nil, trailing: NSAttributedString? = nil,
        column: CGFloat = MenuLayout.headerWidth - 50
    ) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let muted: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: MenuColor.muted]
        let title = NSMutableAttributedString(string: primary, attributes: [.font: font])
        if let secondary {
            title.append(NSAttributedString(string: "  \(secondary)", attributes: muted))
        }
        // A tab stop left of the text end would push the trailing part onto a second line.
        let leadingWidth = title.size().width
        if let trailing, trailing.length > 0 {
            title.append(NSAttributedString(string: "\t", attributes: muted))
            title.append(trailing)
        }
        let paragraph = NSMutableParagraphStyle()
        let tabLocation = max(column, leadingWidth + trailingGap)
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabLocation)]
        title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        return title
    }

    // MARK: - Private

    private func errorItems() -> [NSMenuItem] {
        let unreachable = model.errorMessage.map { [errorLine($0), action("Retry") { $0.refresh() }] } ?? []
        let failedAction = model.actionError.map { [errorLine($0)] } ?? []
        let items = unreachable + failedAction
        return items.isEmpty ? [] : items + [.separator()]
    }

    private func errorLine(_ message: String) -> NSMenuItem {
        let item = NSMenuItem(title: MenuText.truncated(message, max: 72), action: nil, keyEquivalent: "")
        item.image = MenuGlyph.down.image
        item.toolTip = message
        item.isEnabled = false
        return item
    }

    /// Project, then device, then sensors, like the project submenus. Down comes before warning;
    /// the glyph tells them apart, so there are no section titles.
    private func problemItems() -> [NSMenuItem] {
        let problems = model.problems.down + model.problems.warning
        return Self.grouped(problems, by: { devicesById[$0.deviceId]?.project.id }).flatMap { projectGroup in
            let projectLine = devicesById[projectGroup[0].deviceId].map { [pathLine($0.project.displayName, emphasized: true)] }
            return (projectLine ?? []) + Self.grouped(projectGroup, by: \.deviceId).flatMap { deviceGroup in
                [deviceLine(deviceGroup[0])] + deviceGroup.map { sensorItem(row($0), showDevice: false) }
            }
        }
    }

    /// Keeps the problem order: a group appears where its first problem would.
    private static func grouped<Key: Hashable>(_ items: [ProblemItem], by key: (ProblemItem) -> Key) -> [[ProblemItem]] {
        var order: [Key] = []
        var groups: [Key: [ProblemItem]] = [:]
        for item in items {
            let itemKey = key(item)
            if groups[itemKey] == nil { order.append(itemKey) }
            groups[itemKey, default: []].append(item)
        }
        return order.compactMap { groups[$0] }
    }

    /// Below a project line only the subgroups and the device remain; without a project the full group path.
    private func deviceLine(_ item: ProblemItem) -> NSMenuItem {
        let heading = devicesById[item.deviceId]?.device.heading
            ?? ProjectBuilder.heading(path: item.groupPath, deviceName: item.deviceName)
        return pathLine(heading, emphasized: false)
    }

    /// A plain item would start after the icon column; a view starts at the left edge.
    private func pathLine(_ text: String, emphasized: Bool) -> NSMenuItem {
        let line = headerItem(PathLineView(text: text, emphasized: emphasized))
        line.title = text
        line.toolTip = text
        return line
    }

    private func statusCounts(_ project: Project) -> NSAttributedString {
        let counts = [
            (MenuGlyph.down, project.downCount),
            (MenuGlyph.warning, project.warningCount),
            (MenuGlyph.unusual, project.unusualCount),
        ]
            .filter { $0.1 > 0 }
        let result = NSMutableAttributedString()
        for (index, (glyph, count)) in counts.enumerated() {
            let attachment = NSTextAttachment()
            attachment.image = glyph.image
            attachment.bounds = CGRect(x: 0, y: -2, width: 13, height: 13)
            result.append(MenuText.muted(index == 0 ? "" : "  "))
            result.append(NSAttributedString(attachment: attachment))
            result.append(MenuText.muted(" \(count)"))
        }
        return result
    }

    private func projectSection() -> [NSMenuItem] {
        guard !model.projects.isEmpty else { return [] }
        return [.sectionHeader(title: "PROJECTS")] + model.projects.map(projectItem)
    }

    private func projectItem(_ project: Project) -> NSMenuItem {
        let item = NSMenuItem(title: project.displayName, action: nil, keyEquivalent: "")
        let hasProbeSuffix = project.displayName != project.name
        item.attributedTitle = Self.rowTitle(
            MenuText.truncated(project.name, max: 40),
            secondary: hasProbeSuffix ? "· \(MenuText.truncated(project.probeName, max: 24))" : nil,
            trailing: statusCounts(project),
            column: trailingColumn
        )
        item.image = MenuGlyph(status: project.worstStatus).image
        item.submenu = LazyMenu { projectItems(project) }
        return item
    }

    private func prtgItems() -> [NSMenuItem] {
        let refresh = action("Refresh", key: "r") { $0.refresh() }
        if let lastUpdated = model.lastUpdated {
            refresh.attributedTitle = Self.rowTitle("Refresh", secondary: MenuText.updatedAgo(lastUpdated, now: now))
        }
        return [action("Open PRTG", key: "o") { $0.openPRTG() }, refresh]
    }

    private func appItems() -> [NSMenuItem] {
        [
            action("Settings…", key: ",") { $0.openSettings() },
            .separator(),
            action("Quit PRTGBar", key: "q") { $0.quit() },
        ]
    }

    private func breadcrumb(for item: ProblemItem) -> String {
        guard let entry = devicesById[item.deviceId] else { return item.breadcrumb }
        let project = entry.project
        let projectPart = project.name == project.probeName ? [] : [project.name]
        return ([project.probeName] + projectPart + [entry.device.heading])
            .filter { !$0.isEmpty }.joined(separator: " › ")
    }
}
