import AppKit

// MARK: - Time Helpers

extension MenuBuilder {
    static let morningHour = 8
    static let acknowledgedLimit = 50

    static func nextMorning(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: morningHour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(86_400)
    }

    static func minutesUntilNextMorning(from date: Date, calendar: Calendar = .current) -> Int {
        let seconds = nextMorning(after: date, calendar: calendar).timeIntervalSince(date)
        return max(1, Int((seconds / 60).rounded(.up)))
    }
}

// MARK: - Submenus

extension MenuBuilder.Context {
    func sensorDetailMenu(_ row: MenuBuilder.SensorRow) -> NSMenu {
        let header = SensorDetailHeaderView(
            name: row.name,
            statusLine: statusLine(row),
            statusColor: MenuGlyph(status: row.status).color,
            message: row.message,
            history: history(row.id),
            breadcrumb: row.breadcrumb
        )
        let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        pause.submenu = pauseMenu(objectId: row.id)
        let acknowledge = row.isAcknowledged ? [] : [action("Acknowledge…") { $0.acknowledge(sensorIds: [row.id]) }]
        return MenuBuilder.makeMenu([headerItem(header), .separator()] + acknowledge + [
            pause,
            .separator(),
            action("Open in PRTG") { $0.open(objectId: row.id) },
            action("Copy Sensor Name") { $0.copy(row.name) },
            action("Copy Sensor ID") { $0.copy(String(row.id)) },
        ])
    }

    func projectMenu(_ project: Project) -> NSMenu {
        let devices = project.devices.count == 1 ? "1 device" : "\(project.devices.count) devices"
        let sensors = project.sensorCount == 1 ? "1 sensor" : "\(project.sensorCount) sensors"
        let header = ProjectHeaderView(
            name: project.displayName,
            detail: "\(project.probeName) · \(devices) · \(sensors)"
        )
        let deviceItems = project.devices.flatMap { device in
            [NSMenuItem.sectionHeader(title: MenuText.truncated(device.heading))]
                + device.problemSensors.map { sensorItem(row(node: $0), showDevice: false) }
                + [quietItem(device.quietSummary)]
        }
        return MenuBuilder.makeMenu([headerItem(header)] + deviceItems + [
            .separator(),
            action("Open Project in PRTG") { $0.open(objectId: project.id) },
        ])
    }

    func acknowledgedItems() -> [NSMenuItem] {
        let problems = model.problems
        let count = problems.acknowledged.count + problems.paused.reduce(0) { $0 + $1.pausedCount }
        guard count > 0 else { return [] }
        let item = NSMenuItem(title: "Acknowledged & Paused (\(count))", action: nil, keyEquivalent: "")
        item.image = MenuGlyph.acknowledged.image
        item.submenu = acknowledgedMenu()
        return [item]
    }

    func snoozeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Snooze Notifications", action: nil, keyEquivalent: "")
        var options = [
            action("1 Hour") { $0.snooze(until: Date().addingTimeInterval(3600)) },
            action("Until 08:00") { $0.snooze(until: MenuBuilder.nextMorning(after: Date())) },
        ]
        if let until = model.snoozedUntil {
            let time = until.formatted(date: .omitted, time: .shortened)
            options = [quietItem("Snoozed until \(time)"), .separator()] + options
                + [.separator(), action("Off") { $0.snooze(until: nil) }]
        }
        item.submenu = MenuBuilder.makeMenu(options)
        return item
    }

    // MARK: - Private

    private func acknowledgedMenu() -> NSMenu {
        let (entries, remaining) = model.problems.cappedEntries(limit: MenuBuilder.acknowledgedLimit)
        let headings = entries.compactMap { entry -> String? in
            if case .pausedDevice(let line) = entry { return line.heading }
            return nil
        }
        let duplicated = Set(Dictionary(grouping: headings, by: { $0 }).filter { $1.count > 1 }.keys)
        let items = entries.flatMap { entry -> [NSMenuItem] in
            switch entry {
            case .sensor(let problem):
                [sensorItem(row(problem))]
            case .pausedDevice(let line):
                pausedItems(line, showProject: duplicated.contains(line.heading))
            }
        }
        let more: [NSMenuItem] = remaining > 0 ? [.separator(), action("\(remaining) more in PRTG") { $0.openPRTG() }] : []
        return MenuBuilder.makeMenu(items + more)
    }

    private func pausedItems(_ line: PausedDeviceLine, showProject: Bool) -> [NSMenuItem] {
        let heading = NSMenuItem.sectionHeader(title: MenuText.truncated(line.heading))
        if showProject, let project = devicesById[line.deviceId]?.project {
            heading.attributedTitle = sectionTitle(MenuText.truncated(line.heading), suffix: project.name)
        }
        let text = line.pausedCount == 1 ? "1 sensor paused" : "\(line.pausedCount) sensors paused"
        let item = action(text) { $0.open(objectId: line.deviceId) }
        item.image = MenuGlyph.paused.image
        return [heading, item]
    }

    private func sectionTitle(_ heading: String, suffix: String) -> NSAttributedString {
        let font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let title = NSMutableAttributedString(
            string: heading, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        title.append(NSAttributedString(
            string: " · \(MenuText.truncated(suffix, max: 24))",
            attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        return title
    }

    private func pauseMenu(objectId: Int) -> NSMenu {
        MenuBuilder.makeMenu([
            action("1 Hour") { $0.pause(objectId: objectId, minutes: 60) },
            action("Until 08:00") {
                $0.pause(objectId: objectId, minutes: MenuBuilder.minutesUntilNextMorning(from: Date()))
            },
            action("Indefinitely") { $0.pause(objectId: objectId, minutes: nil) },
        ])
    }

    private func quietItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func row(node: TreeNode) -> MenuBuilder.SensorRow {
        if let problem = problemsById[node.id] { return row(problem) }
        return MenuBuilder.SensorRow(
            id: node.id,
            name: node.name,
            status: node.status,
            message: node.message.map { SensorMessage($0).text },
            deviceName: "",
            breadcrumb: "",
            since: node.lastDown,
            isAcknowledged: false
        )
    }

    private func statusLine(_ row: MenuBuilder.SensorRow) -> String {
        let label = row.isAcknowledged ? "Acknowledged, \(row.status.notificationLabel)" : row.status.notificationLabel
        guard let since = row.since else { return label }
        let sameDay = Calendar.current.isDate(since, inSameDayAs: now)
        let time = since.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        let duration = formatDuration(now.timeIntervalSince(since))
        return duration.isEmpty ? "\(label) since \(time)" : "\(label) for \(duration) · since \(time)"
    }
}
