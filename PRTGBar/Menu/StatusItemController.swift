import AppKit
import Combine

extension Notification.Name {
    static let prtgBarOpenSettings = Notification.Name("PRTGBarOpenSettings")
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, MenuActions {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var isMenuOpen = false
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        observe()
        updateStatusItem()
        // An empty menu might not open at all, so menuNeedsUpdate would never get the chance to fill it.
        rebuildMenu()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        appState.updateMenuModel()
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    // MARK: - MenuActions

    func openPRTG() {
        open(path: "/", objectId: nil)
    }

    func refresh() {
        Task { await appState.refresh() }
    }

    func openSettings() {
        NotificationCenter.default.post(name: .prtgBarOpenSettings, object: nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func open(objectId: Int) {
        let page = switch appState.findNode(id: objectId)?.kind {
        case .device: "/device.htm"
        case .group: "/group.htm"
        case .probedevice: "/probenode.htm"
        case .sensor, nil: "/sensor.htm"
        }
        open(path: page, objectId: objectId)
    }

    func acknowledge(sensorIds: [Int]) {
        guard let message = askAcknowledgeMessage() else { return }
        Task { await appState.acknowledge(ids: sensorIds, message: message.isEmpty ? nil : message) }
    }

    func pause(objectId: Int, minutes: Int?) {
        Task { await appState.pause(id: objectId, minutes: minutes) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func snooze(until date: Date?) {
        appState.snooze(until: date)
    }

    // MARK: - Private

    private func observe() {
        // @Published emits on willSet, so the new model arrives as the value instead of being read back.
        appState.$menuModel
            .dropFirst()
            .sink { [weak self] model in
                MainActor.assumeIsolated { self?.modelDidChange(model) }
            }
            .store(in: &cancellables)

        // Settings toggles (badge count, warning indicator) change the item without a new menu model.
        appState.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateStatusItem() }
            }
            .store(in: &cancellables)
    }

    private func modelDidChange(_ model: MenuModel) {
        updateStatusItem(model: model)
        // The poll timer runs in .common modes, so refreshes arrive while the menu is tracking.
        if isMenuOpen { rebuildMenu(model: model) }
    }

    private func rebuildMenu(model: MenuModel? = nil) {
        let history = appState.history
        let built = MenuBuilder.build(
            model ?? appState.menuModel,
            history: { history.summary(for: $0, now: Date()) },
            actions: self
        )
        let items = built.items
        built.removeAllItems()
        menu.items = items
    }

    private func updateStatusItem(model: MenuModel? = nil) {
        guard let button = statusItem.button else { return }
        let state = StatusItemState.make(
            model: model ?? appState.menuModel,
            showCount: appState.showBadgeCount,
            showWarningIndicator: appState.showWarningIndicator
        )
        button.image = StatusIcon.image(for: state)
        button.imagePosition = .imageLeading
        button.title = state.countText
        button.appearsDisabled = state == .unreachable
        button.setAccessibilityLabel(StatusIcon.accessibilityLabel(for: state))
    }

    private func askAcknowledgeMessage() -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Optional message"
        let alert = NSAlert()
        alert.messageText = "Acknowledge Alarm"
        alert.informativeText = "The message is shown in PRTG next to the acknowledgement."
        alert.accessoryView = field
        alert.addButton(withTitle: "Acknowledge")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func open(path: String, objectId: Int?) {
        let serverURL = DemoData.isEnabled ? DemoData.serverURL : appState.serverURL
        let base = serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: base.contains("://") ? base : "https://\(base)") else { return }
        // The web UI listens on the default HTTPS port even when the API uses another one.
        components.port = nil
        components.path = path
        components.queryItems = objectId.map { [URLQueryItem(name: "id", value: "\($0)")] }
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Status Icon

@MainActor
private enum StatusIcon {
    static func image(for state: StatusItemState) -> NSImage? {
        guard let base = NSImage(named: "MenubarIcon") else { return nil }
        base.isTemplate = true
        switch state {
        case .allUp, .down: return base
        case .unreachable: return composite(base, badge: nil, slashed: true)
        case .warningsOnly: return composite(base, badge: symbol("exclamationmark.triangle.fill", size: 8), slashed: false)
        case .snoozed: return composite(base, badge: symbol("bell.slash", size: 11), slashed: false)
        }
    }

    static func accessibilityLabel(for state: StatusItemState) -> String {
        switch state {
        case .allUp: "PRTG: all sensors up"
        case .warningsOnly(let count): count > 0 ? "PRTG: \(count) warnings" : "PRTG: warnings"
        case .down(let count): count > 0 ? "PRTG: \(count) sensors down" : "PRTG: sensors down"
        case .unreachable: "PRTG: server not reachable"
        case .snoozed: "PRTG: notifications snoozed"
        }
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold))
    }

    private static func composite(_ base: NSImage, badge: NSImage?, slashed: Bool) -> NSImage {
        let gap: CGFloat = 2
        let badgeWidth = badge.map { $0.size.width + gap } ?? 0
        let size = NSSize(width: base.size.width + badgeWidth, height: base.size.height)
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        if slashed { drawSlash(in: NSRect(origin: .zero, size: base.size)) }
        if let badge {
            let origin = NSPoint(x: base.size.width + gap, y: (size.height - badge.size.height) / 2)
            badge.draw(in: NSRect(origin: origin, size: badge.size))
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Cuts a gap first so the slash stays readable on top of the template icon.
    private static func drawSlash(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 1))
        path.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 1))
        path.lineCapStyle = .round
        NSGraphicsContext.current?.compositingOperation = .clear
        path.lineWidth = 3.5
        path.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
