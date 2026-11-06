import SwiftUI
import Combine
import UserNotifications
import os

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var treeNodes: [TreeNode] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var actionError: String?
    @Published var lastUpdated: Date?
    @Published var isConfigured = false
    @Published private(set) var menuModel = MenuModel.make(MenuModel.Input())

    let history = StatusHistory(fileURL: DemoData.isEnabled ? nil : StatusHistory.defaultFileURL)

    // MARK: - Settings (persisted)

    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("refreshInterval") var refreshInterval: Double = 60
    @AppStorage("notificationSound") var notificationSound = true
    @AppStorage("notifyOnDown") var notifyOnDown = true
    @AppStorage("notifyOnWarning") var notifyOnWarning = false
    @AppStorage("showBadgeCount") var showBadgeCount = true
    @AppStorage("acceptSelfSignedCerts") var acceptSelfSignedCerts = true
    @AppStorage("showWarningIndicator") var showWarningIndicator = false
    @AppStorage("problemSort") var problemSort = ProblemSort.newestFirst.rawValue
    @AppStorage("showHistory") var showHistory = true
    @AppStorage("notifyOnRecovery") var notifyOnRecovery = true
    @AppStorage("alertExtraChecks") var alertExtraChecks = 1
    @AppStorage("combineAlerts") var combineAlerts = CombineMode.perDevice.rawValue
    @AppStorage("muteFlapping") var muteFlapping = true
    @AppStorage("skipAcknowledgedAndPaused") var skipAcknowledgedAndPaused = true
    @AppStorage("reminderInterval") var reminderInterval: Double = 0
    @AppStorage("snoozedUntil") var snoozedUntil: Double = 0

    // MARK: - API Key (Keychain)

    var apiKey: String {
        get { KeychainService.read(account: "api-key") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainService.delete(account: "api-key")
            } else {
                KeychainService.save(newValue, account: "api-key")
            }
            objectWillChange.send()
        }
    }

    // MARK: - Lifecycle

    func onLaunch() {
        SettingsMigration.run(.standard)
        do {
            try history.load()
        } catch {
            Logger.history.error("Loading status history failed: \(error.localizedDescription)")
        }
        if DemoData.isEnabled {
            loadDemoData()
            return
        }
        if notifyOnDown || notifyOnWarning || notifyOnRecovery {
            requestNotificationPermission()
        }
        startPolling()
    }

    private func loadDemoData() {
        treeNodes = DemoData.buildTree()
        problemTimestamps = DemoData.problemTimestamps
        lastUpdated = Date()
        isConfigured = true
        DemoData.seedHistory(history, now: Date())
        recordHistory(sensorStates(in: treeNodes))
        updateMenuModel()
    }

    // MARK: - Polling

    private var timerCancellable: AnyCancellable?
    private var credentialsRestart: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var alertEngine = AlertEngine()
    private(set) var problemTimestamps: [Int: Date] = [:]

    func startPolling() {
        stopPolling()
        updateMenuModel()
        isConfigured = !serverURL.isEmpty && !apiKey.isEmpty
        guard isConfigured else { return }

        Task { await refresh() }

        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
    }

    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// Settings store every keystroke, so polling restarts once typing pauses instead of per character.
    func credentialsDidChange() {
        credentialsRestart?.cancel()
        credentialsRestart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.startPolling()
        }
    }

    func refresh() async {
        guard !DemoData.isEnabled, !serverURL.isEmpty, !apiKey.isEmpty else { return }
        // One fetch at a time, so an older response can never reach AlertEngine after a newer one.
        if let running = refreshTask { return await running.value }
        let task = Task { await fetchAndApply() }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    private func fetchAndApply() async {
        isLoading = true
        lastError = nil

        do {
            let objects = try await Task.detached { [serverURL, apiKey, acceptSelfSignedCerts] in
                try await PrtgClient.fetchObjects(
                    serverURL: serverURL, token: apiKey, acceptSelfSignedCerts: acceptSelfSignedCerts
                )
            }.value
            apply(objects)
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
        updateMenuModel()
    }

    private func apply(_ objects: [PrtgObject]) {
        let tree = TreeBuilder.buildTree(from: objects)

        updateProblemTimestamps(objects: objects)
        deliverAlerts(for: tree)
        recordHistory(sensorStates(in: tree))

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            treeNodes = tree
            lastUpdated = Date()
            lastError = nil
            actionError = nil
        }
    }

    func testConnection() async -> Bool {
        do {
            return try await Task.detached { [serverURL, apiKey, acceptSelfSignedCerts] in
                try await PrtgClient.testConnection(
                    serverURL: serverURL, token: apiKey, acceptSelfSignedCerts: acceptSelfSignedCerts
                )
            }.value
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Write Actions

    func acknowledge(ids: [Int], message: String?) async {
        await performWrite { serverURL, apiKey, acceptSelfSignedCerts in
            try await PrtgClient.acknowledgeAlarm(
                objectIds: ids, message: message,
                serverURL: serverURL, token: apiKey, acceptSelfSignedCerts: acceptSelfSignedCerts
            )
        }
    }

    func pause(id: Int, minutes: Int?) async {
        await performWrite { serverURL, apiKey, acceptSelfSignedCerts in
            try await PrtgClient.pauseObject(
                objectId: id, minutes: minutes, message: nil,
                serverURL: serverURL, token: apiKey, acceptSelfSignedCerts: acceptSelfSignedCerts
            )
        }
    }

    /// Failures surface through `actionError`, not `lastError`, so a read-only key does not look like an unreachable server.
    private func performWrite(_ write: @escaping @Sendable (String, String, Bool) async throws -> Void) async {
        guard !DemoData.isEnabled else { return }
        do {
            try await Task.detached { [serverURL, apiKey, acceptSelfSignedCerts] in
                try await write(serverURL, apiKey, acceptSelfSignedCerts)
            }.value
            actionError = nil
            await refresh()
        } catch {
            actionError = error.localizedDescription
            updateMenuModel()
        }
    }

    // MARK: - Menu

    func snooze(until date: Date?) {
        snoozedUntil = date?.timeIntervalSince1970 ?? 0
        updateMenuModel()
    }

    func updateMenuModel(now: Date = Date()) {
        let snoozeEnd = Date(timeIntervalSince1970: snoozedUntil)
        menuModel = MenuModel.make(MenuModel.Input(
            roots: treeNodes,
            timestamps: problemTimestamps,
            sort: ProblemSort(rawValue: problemSort) ?? .newestFirst,
            serverURL: DemoData.isEnabled ? DemoData.serverURL : serverURL,
            hasAPIKey: DemoData.isEnabled || !apiKey.isEmpty,
            lastUpdated: lastUpdated,
            error: lastError,
            actionError: actionError,
            snoozedUntil: snoozeEnd > now ? snoozeEnd : nil,
            showHistory: showHistory
        ))
    }

    private func recordHistory(_ states: [Int: SensorStatus]) {
        let now = Date()
        history.record(states, at: now)
        history.saveIfNeeded(now: now)
    }

    func onTerminate() {
        do {
            try history.save()
        } catch {
            Logger.history.error("Saving status history failed: \(error.localizedDescription)")
        }
    }

    private func sensorStates(in nodes: [TreeNode]) -> [Int: SensorStatus] {
        nodes.reduce(into: [:]) { states, node in
            if node.kind == .sensor { states[node.id] = node.status }
            states.merge(sensorStates(in: node.children)) { first, _ in first }
        }
    }

    func findNode(id: Int) -> TreeNode? {
        var stack = treeNodes
        while let node = stack.popLast() {
            if node.id == id { return node }
            stack.append(contentsOf: node.children)
        }
        return nil
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func updateProblemTimestamps(objects: [PrtgObject]) {
        var timestamps = problemTimestamps
        for sensor in objects where sensor.kind == .sensor {
            guard let status = sensor.status else { continue }
            if SensorStatus.problemStatuses.contains(status) {
                if timestamps[sensor.id] == nil { timestamps[sensor.id] = Date() }
            } else {
                timestamps.removeValue(forKey: sensor.id)
            }
        }
        problemTimestamps = timestamps
    }

    private func makeAlertConfig(now: Date) -> AlertConfig {
        var config = AlertConfig()
        config.alertOnDown = notifyOnDown
        config.alertOnWarning = notifyOnWarning
        config.alertOnRecovery = notifyOnRecovery
        config.extraChecks = alertExtraChecks
        config.combine = CombineMode(rawValue: combineAlerts) ?? .perDevice
        config.muteFlapping = muteFlapping
        config.skipAcknowledgedAndPaused = skipAcknowledgedAndPaused
        config.reminderInterval = reminderInterval > 0 ? reminderInterval : nil
        let snoozeEnd = Date(timeIntervalSince1970: snoozedUntil)
        config.snoozedUntil = snoozedUntil > 0 && snoozeEnd > now ? snoozeEnd : nil
        return config
    }

    private func deliverAlerts(for tree: [TreeNode]) {
        guard !DemoData.isEnabled else { return }
        let now = Date()
        alertEngine.config = makeAlertConfig(now: now)
        let alerts = alertEngine.process(Self.snapshots(in: tree), at: now)
        NotificationDispatcher.deliver(alerts, soundEnabled: notificationSound)
    }

    static func snapshots(in roots: [TreeNode]) -> [SensorSnapshot] {
        var result: [SensorSnapshot] = []
        func walk(_ node: TreeNode, ancestors: [TreeNode]) {
            if node.kind == .sensor, let device = ancestors.last(where: { $0.kind == .device }) {
                result.append(SensorSnapshot(
                    id: node.id, name: node.name, deviceId: device.id, deviceName: device.name,
                    projectName: ProjectBuilder.projectName(ancestors: ancestors), status: node.status,
                    isAcknowledged: SensorMessage(node.message ?? "").isAcknowledged, message: node.message
                ))
            }
            for child in node.children { walk(child, ancestors: ancestors + [node]) }
        }
        roots.forEach { walk($0, ancestors: []) }
        return result
    }

    // MARK: - Opening PRTG

    func open(objectId: Int) {
        let page = switch findNode(id: objectId)?.kind {
        case .device: "/device.htm"
        case .group: "/group.htm"
        case .probedevice: "/probenode.htm"
        case .sensor, nil: "/sensor.htm"
        }
        open(path: page, objectId: objectId)
    }

    func open(path: String, objectId: Int?) {
        let server = DemoData.isEnabled ? DemoData.serverURL : serverURL
        let base = server
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
