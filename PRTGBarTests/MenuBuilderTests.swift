import AppKit
import SwiftUI
import XCTest
@testable import PRTGBar

@MainActor
final class MenuBuilderTests: XCTestCase {

    func testMainMenuSectionsInOrder() {
        let menu = build(makeModel())
        let titles = menu.items.map(\.title)

        XCTAssertNotNil(menu.items.first?.view, "first item is the summary header view")

        let fixed = ["Shop", "web-01", "HTTP", "Disk Free", "Acknowledged & Paused", "PROJECTS", "Shop", "Open PRTG",
                     "Refresh", "Snooze Notifications", "Settings…", "Quit PRTGBar"]
        let found = titles.compactMap { title in fixed.first { title.hasPrefix($0) } }
        XCTAssertEqual(found, fixed)

        XCTAssertTrue(menu.items[1].isSeparatorItem, "separator below the header")
        XCTAssertFalse(titles.contains { $0 == "DOWN" || $0 == "WARNING" || $0.hasPrefix("About") })
        let start = problemStart(in: menu)
        XCTAssertNotNil(menu.items[start + 2].submenu)
    }

    func testProblemsAreGroupedUnderDevicePathLines() throws {
        let now = Date()
        func sensor(_ id: Int, minutesAgo: Double) -> TreeNode {
            TreeNode(id: id, name: "S\(id)", kind: .sensor, status: .down, lastDown: now.addingTimeInterval(-minutesAgo * 60))
        }
        let apiDevice = TreeNode(id: 100, name: "api", kind: .device, status: .down,
                                 children: [sensor(1, minutesAgo: 1), sensor(3, minutesAgo: 30)])
        let dbDevice = TreeNode(id: 200, name: "db", kind: .device, status: .down, children: [sensor(2, minutesAgo: 10)])
        let customer = TreeNode(id: 10, name: "vhw", kind: .group, status: .down, children: [
            TreeNode(id: 11, name: "Middleware", kind: .group, status: .down, children: [apiDevice, dbDevice]),
        ])
        let menu = build(menuModelFor(customer, now: now))

        let start = problemStart(in: menu)
        let section = menu.items[start...].prefix { !$0.isSeparatorItem && !$0.isSectionHeader }
        let titles = section.map { $0.title.components(separatedBy: "\t")[0] }
        XCTAssertEqual(titles, ["vhw", "Middleware › api", "S1", "S3", "Middleware › db", "S2"])

        for line in menu.items[start...(start + 1)] {
            XCTAssertNotNil(line.view, "own view, so the line starts at the left edge instead of after the icon column")
            XCTAssertNil(line.submenu)
        }
        let sensorLine = menu.items[start + 2]
        XCTAssertEqual(sensorLine.indentationLevel, 0)
        XCTAssertNotNil(sensorLine.submenu)
        XCTAssertFalse(try XCTUnwrap(sensorLine.attributedTitle?.string).contains("api"))
    }

    func testTrailingTextNeverWrapsBelowLongTitles() throws {
        let primary = String(repeating: "W", count: 40)
        let title = MenuBuilder.Context.rowTitle(primary, secondary: "device", trailing: MenuText.muted("5d 2h"))
        let style = try XCTUnwrap(title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let leading = NSAttributedString(string: "\(primary)  device", attributes: [.font: NSFont.menuFont(ofSize: 0)])

        XCTAssertGreaterThan(try XCTUnwrap(style.tabStops.first).location, leading.size().width)
    }

    func testDurationsShareOneColumn() throws {
        let long = String(repeating: "W", count: 40)
        let web = TreeNode(id: 100, name: "web", kind: .device, status: .down, children: [
            TreeNode(id: 1, name: "A", kind: .sensor, status: .down, lastDown: Date().addingTimeInterval(-60)),
            TreeNode(id: 2, name: long, kind: .sensor, status: .down, lastDown: Date().addingTimeInterval(-120)),
        ])
        let menu = build(MenuModel.make(MenuModel.Input(
            roots: [TreeNode(id: 10, name: "Shop", kind: .group, status: .down, children: [web])],
            serverURL: "https://prtg.example.com", hasAPIKey: true, lastUpdated: Date()
        )))
        func column(_ item: NSMenuItem) throws -> CGFloat {
            let title = try XCTUnwrap(item.attributedTitle)
            let style = try XCTUnwrap(title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            return try XCTUnwrap(style.tabStops.first).location
        }

        let start = problemStart(in: menu)
        let short = try column(menu.items[start + 2])
        let wide = try column(menu.items[start + 3])
        XCTAssertEqual(short, wide)
        let longWidth = NSAttributedString(string: long, attributes: [.font: NSFont.menuFont(ofSize: 0)]).size().width
        XCTAssertGreaterThan(short, longWidth)
    }

    func testProjectCountsUseStatusGlyphs() throws {
        let menu = build(makeModel())
        let shop = try XCTUnwrap(project("Shop", in: menu)?.attributedTitle)
        var attachments = 0
        shop.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shop.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertEqual(attachments, 2, "one glyph for down, one for warning")
        XCTAssertFalse(shop.string.contains("▲") || shop.string.contains("✕"))
    }

    func testAcknowledgedIsSeparatedFromProblems() {
        let menu = build(makeModel())
        let acknowledged = index(of: "Acknowledged & Paused", in: menu)
        XCTAssertTrue(menu.items[acknowledged - 1].isSeparatorItem)
    }

    func testMutedColourKeepsContrastInBothAppearances() throws {
        for (name, expected) in [(NSAppearance.Name.aqua, 0.30), (.darkAqua, 0.80)] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            var white: CGFloat = -1
            appearance.performAsCurrentDrawingAppearance {
                white = MenuColor.muted.usingColorSpace(.genericGamma22Gray)?.whiteComponent ?? -1
            }
            XCTAssertEqual(white, expected, accuracy: 0.01, "\(name)")
        }
        XCTAssertEqual(MenuText.muted("x").attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, MenuColor.muted)
    }

    func testProjectHeaderKeepsTheSummaryOnOneLine() {
        func height(_ summary: StatusSummary) -> CGFloat {
            NSHostingView(rootView: ProjectHeaderView(name: "vhw", summary: summary, detail: "8 devices · 56 sensors"))
                .fittingSize.height
        }
        let short = height(StatusSummary(up: 45, down: 0, warning: 3, paused: 0, unknown: 0))
        let long = height(StatusSummary(up: 45, down: 12, warning: 3, paused: 2, unknown: 0, unusual: 6))
        XCTAssertEqual(long, short, accuracy: 0.5, "the summary line must not wrap")
    }

    func testKeyEquivalents() {
        let menu = build(makeModel())

        XCTAssertEqual(item("Open PRTG", in: menu)?.keyEquivalent, "o")
        XCTAssertEqual(item("Refresh", in: menu)?.keyEquivalent, "r")
        XCTAssertEqual(item("Settings…", in: menu)?.keyEquivalent, ",")
        XCTAssertEqual(item("Quit PRTGBar", in: menu)?.keyEquivalent, "q")
    }

    func testProjectSubmenuListsEverySensorUnderItsDevice() throws {
        let menu = build(makeModel())
        let shop = populated(try XCTUnwrap(project("Shop", in: menu)?.submenu))

        XCTAssertNotNil(shop.items.first?.view, "project header view")
        let heading = try XCTUnwrap(shop.items.firstIndex { $0.isSectionHeader })
        XCTAssertEqual(shop.items[heading].title, "web-01")
        let sensors = shop.items[(heading + 1)...].prefix { !$0.isSeparatorItem && !$0.isSectionHeader }
        XCTAssertEqual(sensors.map { $0.title.components(separatedBy: "\t")[0] }, ["HTTP", "Disk Free", "CPU", "Ping"],
                       "problems first, then the rest by name")
        XCTAssertTrue(sensors.allSatisfy { $0.submenu != nil }, "every sensor has its detail submenu")
        XCTAssertEqual(sensors.last?.title, "Ping\t12 msec", "last value in the trailing column")
        XCTAssertFalse(shop.items.contains { $0.title.contains("more up") })
        XCTAssertNotNil(shop.items.first { $0.title == "Open Project in PRTG" })
    }

    func testOpeningAHealthySensorFromTheProject() throws {
        let actions = RecordingActions()
        let menu = MenuBuilder.build(makeModel(), history: { _ in nil }, actions: actions)
        let office = populated(try XCTUnwrap(project("Office", in: menu)?.submenu))

        let detail = populated(try XCTUnwrap(office.items.first { $0.title.hasPrefix("Ping") }?.submenu))
        XCTAssertNil(detail.items.first { $0.title == "Acknowledge…" }, "nothing to acknowledge on an up sensor")
        trigger(try XCTUnwrap(detail.items.first { $0.title == "Open in PRTG" }))
        XCTAssertEqual(actions.opened, [6])
    }

    func testSensorSubmenuActions() throws {
        let actions = RecordingActions()
        let menu = MenuBuilder.build(makeModel(), history: { _ in nil }, actions: actions)
        let start = problemStart(in: menu)
        let detail = populated(try XCTUnwrap(menu.items[start + 2].submenu))

        XCTAssertNotNil(detail.items.first?.view, "sensor detail header view")
        let titles = detail.items.filter { !$0.isSeparatorItem && $0.view == nil }.map(\.title)
        XCTAssertEqual(titles, ["Acknowledge…", "Pause", "Open in PRTG", "Copy Sensor Name", "Copy Sensor ID"])

        let pause = try XCTUnwrap(detail.items.first { $0.title == "Pause" }?.submenu)
        XCTAssertEqual(pause.items.map(\.title), ["1 Hour", "Until 08:00", "Indefinitely"])

        trigger(try XCTUnwrap(detail.items.first { $0.title == "Copy Sensor ID" }))
        trigger(try XCTUnwrap(detail.items.first { $0.title == "Acknowledge…" }))
        trigger(try XCTUnwrap(pause.items.first { $0.title == "1 Hour" }))
        trigger(try XCTUnwrap(pause.items.first { $0.title == "Indefinitely" }))
        XCTAssertEqual(actions.copied, ["1"])
        XCTAssertEqual(actions.acknowledged, [[1]])
        XCTAssertEqual(actions.paused.map(\.id), [1, 1])
        XCTAssertEqual(actions.paused.map(\.minutes), [60, nil])
    }

    func testWarningSensorDetailHasNoAcknowledge() throws {
        let menu = build(makeModel())
        let detail = populated(try XCTUnwrap(menu.items[problemStart(in: menu) + 3].submenu))
        let titles = detail.items.filter { !$0.isSeparatorItem && $0.view == nil }.map(\.title)

        XCTAssertEqual(titles, ["Pause", "Open in PRTG", "Copy Sensor Name", "Copy Sensor ID"])
    }

    func testSensorDetailOmitsHistoryWhenDisabled() throws {
        for (showHistory, expectedCalls) in [(true, true), (false, false)] {
            var requested: [Int] = []
            let menu = MenuBuilder.build(
                makeModel(showHistory: showHistory),
                history: { requested.append($0); return nil },
                actions: RecordingActions()
            )
            let start = problemStart(in: menu)
            let detail = populated(try XCTUnwrap(menu.items[start + 2].submenu))
            XCTAssertNotNil(detail.items.first?.view)
            XCTAssertEqual(!requested.isEmpty, expectedCalls, "showHistory \(showHistory)")
        }
    }

    func testSubmenusAreBuiltWhenOpened() throws {
        var requested: [Int] = []
        let menu = MenuBuilder.build(makeModel(), history: { requested.append($0); return nil },
                                     actions: RecordingActions())
        let detail = try XCTUnwrap(menu.items[problemStart(in: menu) + 2].submenu)
        let projectMenu = try XCTUnwrap(project("Shop", in: menu)?.submenu)

        XCTAssertTrue(detail.items.isEmpty)
        XCTAssertTrue(projectMenu.items.isEmpty)
        XCTAssertTrue(requested.isEmpty)

        XCTAssertFalse(populated(detail).items.isEmpty)
        XCTAssertFalse(populated(projectMenu).items.isEmpty)
        XCTAssertEqual(requested, [1])
    }

    func testNoMoreThanTwoSubmenuLevels() {
        let menu = build(makeModel())
        XCTAssertLessThanOrEqual(depth(of: menu), 2)
    }

    func testAcknowledgedAndPausedSubmenu() throws {
        let menu = build(makeModel())
        let submenu = try XCTUnwrap(item("Acknowledged & Paused", in: menu)?.submenu)

        XCTAssertTrue(submenu.items.contains { $0.title.hasPrefix("Backup") && $0.submenu != nil })
        XCTAssertTrue(submenu.items.contains { $0.isSectionHeader && $0.title == "web-01" })
        XCTAssertTrue(submenu.items.contains { $0.title == "1 sensor paused" })
    }

    func testUnconfiguredShowsSetUpItem() {
        let model = MenuModel.make(MenuModel.Input())
        let menu = build(model)

        XCTAssertNotNil(item("Set up PRTG…", in: menu))
        XCTAssertNil(item("Shop", in: menu))
        XCTAssertNotNil(item("Quit PRTGBar", in: menu))
    }

    func testErrorShowsRetry() throws {
        let model = makeModel(error: "Network error: offline")
        let menu = build(model)

        let retry = index(of: "Retry", in: menu)
        XCTAssertTrue(menu.items[0].title.hasPrefix("Network error"))
        XCTAssertEqual(retry, 1)

        let actions = RecordingActions()
        let retryItem = MenuBuilder.build(model, history: { _ in nil }, actions: actions).items[retry]
        trigger(retryItem)
        XCTAssertEqual(actions.refreshCount, 1)
    }

    func testActionErrorShowsLineWithoutRetry() {
        let menu = build(makeModel(actionError: "This API key is read-only or lacks permission for this action."))

        XCTAssertTrue(menu.items[0].title.hasPrefix("This API key is read-only"))
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertNil(item("Retry", in: menu))
        XCTAssertNotNil(item("web-01", in: menu), "problems stay visible below a failed action")
    }

    func testSnoozeSubmenuShowsOffOnlyWhenSnoozed() throws {
        let plain = try XCTUnwrap(item("Snooze Notifications", in: build(makeModel()))?.submenu)
        XCTAssertEqual(plain.items.map(\.title), ["1 Hour", "Until 08:00"])

        let snoozed = makeModel(snoozedUntil: Date().addingTimeInterval(600))
        let submenu = try XCTUnwrap(item("Snooze Notifications", in: build(snoozed))?.submenu)
        XCTAssertTrue(submenu.items.contains { $0.title == "Off" })
    }

    func testMinutesUntilNextMorning() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 22)))
        let early = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 7, minute: 30)))

        XCTAssertEqual(MenuBuilder.minutesUntilNextMorning(from: evening, calendar: calendar), 600)
        XCTAssertEqual(MenuBuilder.minutesUntilNextMorning(from: early, calendar: calendar), 30)
    }

    // MARK: - Helpers

    private func makeModel(error: String? = nil, actionError: String? = nil, snoozedUntil: Date? = nil,
                           showHistory: Bool = true) -> MenuModel {
        let web = TreeNode(id: 100, name: "web-01", kind: .device, status: .down, children: [
            TreeNode(id: 1, name: "HTTP", kind: .sensor, status: .down, message: "Timeout"),
            TreeNode(id: 2, name: "Disk Free", kind: .sensor, status: .warning),
            TreeNode(id: 3, name: "Ping", kind: .sensor, status: .up, lastValue: "12 msec"),
            TreeNode(id: 4, name: "CPU", kind: .sensor, status: .paused),
        ])
        let nas = TreeNode(id: 200, name: "nas", kind: .device, status: .up, children: [
            TreeNode(id: 5, name: "Backup", kind: .sensor, status: .down, message: "Acknowledged by admin: later"),
            TreeNode(id: 6, name: "Ping", kind: .sensor, status: .up),
        ])
        let probe = TreeNode(id: 1000, name: "Probe", kind: .probedevice, status: .up, children: [
            TreeNode(id: 10, name: "Shop", kind: .group, status: .down, children: [web]),
            TreeNode(id: 20, name: "Office", kind: .group, status: .up, children: [nas]),
        ])
        return MenuModel.make(MenuModel.Input(
            roots: [probe], serverURL: "https://prtg.example.com", hasAPIKey: true, lastUpdated: Date(),
            error: error, actionError: actionError, snoozedUntil: snoozedUntil, showHistory: showHistory
        ))
    }

    private func build(_ model: MenuModel) -> NSMenu {
        MenuBuilder.build(model, history: { _ in nil }, actions: RecordingActions())
    }

    private func item(_ prefix: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title.hasPrefix(prefix) }
    }

    /// The first problem line, below the header view and its separator.
    private func problemStart(in menu: NSMenu) -> Int {
        (menu.items.firstIndex { $0.view != nil } ?? -2) + 2
    }

    private func menuModelFor(_ root: TreeNode, now: Date) -> MenuModel {
        MenuModel.make(MenuModel.Input(roots: [root], serverURL: "https://prtg.example.com", hasAPIKey: true, lastUpdated: now))
    }

    /// Device lines in the problem sections start with the project name too.
    private func project(_ name: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items[index(of: "PROJECTS", in: menu)...].first { $0.title.hasPrefix(name) }
    }

    private func index(of prefix: String, in menu: NSMenu) -> Int {
        menu.items.firstIndex { $0.title.hasPrefix(prefix) } ?? -1
    }

    private func populated(_ menu: NSMenu) -> NSMenu {
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu
    }

    private func trigger(_ item: NSMenuItem) {
        guard let action = item.action else { return XCTFail("\(item.title) has no action") }
        _ = (item.target as? NSObject)?.perform(action, with: item)
    }

    /// Option lists (Pause, Snooze) are leaves and do not count as a navigation level.
    private func depth(of menu: NSMenu) -> Int {
        let optionLists: Set<String> = ["Pause", "Snooze Notifications"]
        return menu.items
            .filter { $0.submenu != nil && !optionLists.contains($0.title) }
            .compactMap(\.submenu)
            .map { 1 + depth(of: populated($0)) }
            .max() ?? 0
    }
}

@MainActor
private final class RecordingActions: MenuActions {
    var copied: [String] = []
    var acknowledged: [[Int]] = []
    var paused: [(id: Int, minutes: Int?)] = []
    var refreshCount = 0

    func openPRTG() {}
    func refresh() { refreshCount += 1 }
    func openSettings() {}
    func quit() {}
    var opened: [Int] = []
    func open(objectId: Int) { opened.append(objectId) }
    func acknowledge(sensorIds: [Int]) { acknowledged.append(sensorIds) }
    func pause(objectId: Int, minutes: Int?) { paused.append((objectId, minutes)) }
    func copy(_ text: String) { copied.append(text) }
    func snooze(until: Date?) {}
}
