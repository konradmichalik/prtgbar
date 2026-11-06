import AppKit
import XCTest
@testable import PRTGBar

@MainActor
final class MenuBuilderTests: XCTestCase {

    func testMainMenuSectionsInOrder() {
        let menu = build(makeModel())
        let titles = menu.items.map(\.title)

        XCTAssertNotNil(menu.items.first?.view, "first item is the summary header view")

        let fixed = ["DOWN", "WARNING", "Acknowledged & Paused", "PROJECTS", "Open PRTG", "Refresh",
                     "Snooze Notifications", "Settings…", "About PRTGBar", "Quit PRTGBar"]
        let found = titles.compactMap { title in fixed.first { title.hasPrefix($0) } }
        XCTAssertEqual(found, fixed)

        let down = index(of: "DOWN", in: menu)
        let warning = index(of: "WARNING", in: menu)
        XCTAssertTrue(menu.items[down].isSectionHeader)
        XCTAssertTrue(menu.items[down + 1].title.hasPrefix("HTTP"))
        XCTAssertNotNil(menu.items[down + 1].submenu)
        XCTAssertTrue(menu.items[warning + 1].title.hasPrefix("Disk"))
    }

    func testKeyEquivalents() {
        let menu = build(makeModel())

        XCTAssertEqual(item("Open PRTG", in: menu)?.keyEquivalent, "o")
        XCTAssertEqual(item("Refresh", in: menu)?.keyEquivalent, "r")
        XCTAssertEqual(item("Settings…", in: menu)?.keyEquivalent, ",")
        XCTAssertEqual(item("Quit PRTGBar", in: menu)?.keyEquivalent, "q")
    }

    func testProjectSubmenuHasDeviceHeadingsAndQuietLine() throws {
        let menu = build(makeModel())
        let shop = try XCTUnwrap(item("Shop", in: menu)?.submenu)

        XCTAssertNotNil(shop.items.first?.view, "project header view")
        let heading = try XCTUnwrap(shop.items.first { $0.isSectionHeader })
        XCTAssertEqual(heading.title, "web-01")
        let quiet = try XCTUnwrap(shop.items.first { $0.title == "1 more up, 1 paused" })
        XCTAssertFalse(quiet.isEnabled)
        XCTAssertNotNil(shop.items.first { $0.title == "Open Project in PRTG" })

        let office = try XCTUnwrap(item("Office", in: menu)?.submenu)
        XCTAssertNotNil(office.items.first { $0.title == "All 1 sensors up" })
    }

    func testSensorSubmenuActions() throws {
        let actions = RecordingActions()
        let menu = MenuBuilder.build(makeModel(), history: { _ in nil }, actions: actions)
        let down = index(of: "DOWN", in: menu)
        let detail = try XCTUnwrap(menu.items[down + 1].submenu)

        XCTAssertNotNil(detail.items.first?.view, "sensor detail header view")
        let titles = detail.items.filter { !$0.isSeparatorItem && $0.view == nil }.map(\.title)
        XCTAssertEqual(titles, ["Acknowledge…", "Pause", "Open in PRTG", "Copy Sensor Name", "Copy Sensor ID"])

        let pause = try XCTUnwrap(detail.items.first { $0.title == "Pause" }?.submenu)
        XCTAssertEqual(pause.items.map(\.title), ["1 Hour", "Until Tomorrow 08:00", "Indefinitely"])

        trigger(try XCTUnwrap(detail.items.first { $0.title == "Copy Sensor ID" }))
        trigger(try XCTUnwrap(detail.items.first { $0.title == "Acknowledge…" }))
        trigger(try XCTUnwrap(pause.items.first { $0.title == "1 Hour" }))
        trigger(try XCTUnwrap(pause.items.first { $0.title == "Indefinitely" }))
        XCTAssertEqual(actions.copied, ["1"])
        XCTAssertEqual(actions.acknowledged, [[1]])
        XCTAssertEqual(actions.paused.map(\.id), [1, 1])
        XCTAssertEqual(actions.paused.map(\.minutes), [60, nil])
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
        let model = MenuModel.make(roots: [], timestamps: [:], sort: .newestFirst, serverURL: "",
                                   lastUpdated: nil, error: nil, snoozedUntil: nil)
        let menu = build(model)

        XCTAssertNotNil(item("Set up PRTG…", in: menu))
        XCTAssertNil(item("DOWN", in: menu))
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

    func testSnoozeSubmenuShowsOffOnlyWhenSnoozed() throws {
        let plain = try XCTUnwrap(item("Snooze Notifications", in: build(makeModel()))?.submenu)
        XCTAssertEqual(plain.items.map(\.title), ["1 Hour", "Until Tomorrow 08:00"])

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

    private func makeModel(error: String? = nil, snoozedUntil: Date? = nil) -> MenuModel {
        let web = TreeNode(id: 100, name: "web-01", kind: .device, status: .down, children: [
            TreeNode(id: 1, name: "HTTP", kind: .sensor, status: .down, message: "Timeout"),
            TreeNode(id: 2, name: "Disk Free", kind: .sensor, status: .warning),
            TreeNode(id: 3, name: "Ping", kind: .sensor, status: .up),
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
        return MenuModel.make(roots: [probe], timestamps: [:], sort: .newestFirst,
                              serverURL: "https://prtg.example.com", lastUpdated: Date(),
                              error: error, snoozedUntil: snoozedUntil)
    }

    private func build(_ model: MenuModel) -> NSMenu {
        MenuBuilder.build(model, history: { _ in nil }, actions: RecordingActions())
    }

    private func item(_ prefix: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title.hasPrefix(prefix) }
    }

    private func index(of prefix: String, in menu: NSMenu) -> Int {
        menu.items.firstIndex { $0.title.hasPrefix(prefix) } ?? -1
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
            .map { 1 + depth(of: $0) }
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
    func open(objectId: Int) {}
    func acknowledge(sensorIds: [Int]) { acknowledged.append(sensorIds) }
    func pause(objectId: Int, minutes: Int?) { paused.append((objectId, minutes)) }
    func copy(_ text: String) { copied.append(text) }
    func snooze(until: Date?) {}
}
