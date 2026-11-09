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

// MARK: - Glyphs

enum MenuGlyph {
    case down, warning, up, paused, acknowledged

    init(status: SensorStatus) {
        switch status {
        case .down, .partialdown: self = .down
        case .warning, .unusual, .unknown: self = .warning
        case .paused: self = .paused
        case .up: self = .up
        }
    }

    var symbolName: String {
        switch self {
        case .down: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .up: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .acknowledged: "checkmark.circle"
        }
    }

    var color: NSColor {
        switch self {
        case .down: .systemRed
        case .warning: .systemOrange
        case .up: .systemGreen
        case .paused, .acknowledged: .secondaryLabelColor
        }
    }

    var image: NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
        image?.isTemplate = false
        return image
    }
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
        now: Date = Date()
    ) -> NSMenu {
        let context = Context(model: model, history: history, actions: actions, now: now)
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
    }

    @MainActor
    struct Context {
        let model: MenuModel
        let history: (Int) -> HistorySummary?
        weak var actions: MenuActions?
        let now: Date
        let problemsById: [Int: ProblemItem]
        let devicesById: [Int: (project: Project, device: ProjectDevice)]

        init(model: MenuModel, history: @escaping (Int) -> HistorySummary?, actions: MenuActions, now: Date) {
            self.model = model
            self.history = history
            self.actions = actions
            self.now = now
            let problems = model.problems.down + model.problems.warning + model.problems.acknowledged
            problemsById = Dictionary(problems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
        let summary = SummaryHeaderView(host: model.serverHost, summary: model.summary, hasData: model.lastUpdated != nil)
        return errorItems()
            + [headerItem(summary)]
            + sensorSection("DOWN", model.problems.down)
            + sensorSection("WARNING", model.problems.warning)
            + acknowledgedItems()
            + projectSection()
            + [.separator()] + prtgItems()
            + [.separator(), snoozeItem()] + appItems()
    }

    func headerItem<V: View>(_ view: V) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
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
            trailing: row.since.map { formatDuration(now.timeIntervalSince($0)) }
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

    static func rowTitle(_ primary: String, secondary: String? = nil, trailing: String? = nil) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let muted: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let title = NSMutableAttributedString(string: primary, attributes: [.font: font])
        if let secondary {
            title.append(NSAttributedString(string: "  \(secondary)", attributes: muted))
        }
        if let trailing, !trailing.isEmpty {
            title.append(NSAttributedString(string: "\t\(trailing)", attributes: muted))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: MenuLayout.headerWidth - 50)]
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

    private func sensorSection(_ title: String, _ items: [ProblemItem]) -> [NSMenuItem] {
        guard !items.isEmpty else { return [] }
        return [.sectionHeader(title: title)] + items.map { sensorItem(row($0)) }
    }

    private func projectSection() -> [NSMenuItem] {
        guard !model.projects.isEmpty else { return [] }
        return [.sectionHeader(title: "PROJECTS")] + model.projects.map(projectItem)
    }

    private func projectItem(_ project: Project) -> NSMenuItem {
        let item = NSMenuItem(title: project.displayName, action: nil, keyEquivalent: "")
        let counts = [
            project.downCount > 0 ? "✕\(project.downCount)" : nil,
            project.warningCount > 0 ? "▲\(project.warningCount)" : nil,
        ].compactMap { $0 }.joined(separator: " ")
        let hasProbeSuffix = project.displayName != project.name
        item.attributedTitle = Self.rowTitle(
            MenuText.truncated(project.name, max: 40),
            secondary: hasProbeSuffix ? "· \(MenuText.truncated(project.probeName, max: 24))" : nil,
            trailing: counts
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
            ClosureMenuItem(title: "About PRTGBar") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            },
            .separator(),
            action("Quit PRTGBar", key: "q") { $0.quit() },
        ]
    }

    private func breadcrumb(for item: ProblemItem) -> String {
        guard let entry = devicesById[item.deviceId] else { return item.breadcrumb }
        let project = entry.project
        let projectPart = project.name == project.probeName ? [] : [project.name]
        return ([project.probeName] + projectPart + [entry.device.heading]).joined(separator: " › ")
    }
}
