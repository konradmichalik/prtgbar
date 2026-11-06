import SwiftUI
import Combine
import UserNotifications

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    @Published var treeNodes: [TreeNode] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isConfigured = false
    @Published private(set) var menuModel = MenuModel.make(
        roots: [], timestamps: [:], sort: .newestFirst, serverURL: "",
        lastUpdated: nil, error: nil, snoozedUntil: nil
    )

    let history = StatusHistory(fileURL: DemoData.isEnabled ? nil : StatusHistory.defaultFileURL)

    // MARK: - Settings (persisted)

    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("refreshInterval") var refreshInterval: Double = 60
    @AppStorage("notifyOnStatusChange") var notifyOnStatusChange = true
    @AppStorage("notificationSound") var notificationSound = true
    @AppStorage("notifyOnDown") var notifyOnDown = true
    @AppStorage("notifyOnWarning") var notifyOnWarning = false
    @AppStorage("showBadgeCount") var showBadgeCount = true
    @AppStorage("acceptSelfSignedCerts") var acceptSelfSignedCerts = true
    @AppStorage("showAllProbes") var showAllProbes = true
    @AppStorage("showAcknowledged") var showAcknowledged = false
    @AppStorage("showWarningIndicator") var showWarningIndicator = false
    @AppStorage("problemSort") var problemSort = ProblemSort.newestFirst.rawValue
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
        try? history.load()
        if DemoData.isEnabled {
            loadDemoData()
            return
        }
        if notifyOnStatusChange {
            requestNotificationPermission()
        }
        updateMenuModel()
        startPolling()
    }

    private func loadDemoData() {
        treeNodes = DemoData.buildTree()
        problemTimestamps = DemoData.problemTimestamps
        lastUpdated = Date()
        isConfigured = true
        recordHistory(sensorStates(in: treeNodes))
        updateMenuModel()
    }

    // MARK: - Polling

    private var timerCancellable: AnyCancellable?
    private var previousSensorStates: [Int: SensorStatus] = [:]
    private(set) var problemTimestamps: [Int: Date] = [:]

    func startPolling() {
        stopPolling()
        guard !serverURL.isEmpty, !apiKey.isEmpty else { return }
        isConfigured = true

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

    func refresh() async {
        guard !serverURL.isEmpty, !apiKey.isEmpty else { return }

        isLoading = true
        lastError = nil

        do {
            let objects = try await Task.detached { [serverURL, apiKey, acceptSelfSignedCerts] in
                try await PrtgClient.fetchObjects(
                    serverURL: serverURL, token: apiKey, acceptSelfSignedCerts: acceptSelfSignedCerts
                )
            }.value

            let tree = TreeBuilder.buildTree(from: objects)

            detectStatusChanges(objects: objects)
            recordHistory(sensorStates(in: tree))

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                treeNodes = tree
                lastUpdated = Date()
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
        updateMenuModel()
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

    /// Failures surface through `lastError` so the menu shows them, e.g. the read-only copy for 401/403.
    private func performWrite(_ write: @escaping @Sendable (String, String, Bool) async throws -> Void) async {
        guard !DemoData.isEnabled else { return }
        do {
            try await Task.detached { [serverURL, apiKey, acceptSelfSignedCerts] in
                try await write(serverURL, apiKey, acceptSelfSignedCerts)
            }.value
            await refresh()
        } catch {
            lastError = error.localizedDescription
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
        menuModel = MenuModel.make(
            roots: treeNodes,
            timestamps: problemTimestamps,
            sort: ProblemSort(rawValue: problemSort) ?? .newestFirst,
            serverURL: DemoData.isEnabled ? DemoData.serverURL : serverURL,
            lastUpdated: lastUpdated,
            error: lastError,
            snoozedUntil: snoozeEnd > now ? snoozeEnd : nil
        )
    }

    private func recordHistory(_ states: [Int: SensorStatus]) {
        history.record(states, at: Date())
        try? history.save()
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

    private func detectStatusChanges(objects: [PrtgObject]) {
        let sensors = objects.filter { $0.kind == .sensor }
        var newStates: [Int: SensorStatus] = [:]
        var newTimestamps = problemTimestamps

        for sensor in sensors {
            guard let status = sensor.status else { continue }
            newStates[sensor.id] = status

            if SensorStatus.problemStatuses.contains(status) {
                if newTimestamps[sensor.id] == nil {
                    newTimestamps[sensor.id] = Date()
                }
            } else {
                newTimestamps.removeValue(forKey: sensor.id)
            }

            guard notifyOnStatusChange,
                  let previousStatus = previousSensorStates[sensor.id],
                  previousStatus != status else { continue }

            let shouldNotify: Bool
            switch status {
            case .down, .partialdown:
                shouldNotify = notifyOnDown
            case .warning, .unusual:
                shouldNotify = notifyOnWarning
            default:
                shouldNotify = false
            }

            if shouldNotify {
                sendNotification(
                    sensorName: sensor.name,
                    deviceName: sensor.parent?.name,
                    sensorStatus: status,
                    playSound: notificationSound
                )
            }
        }

        previousSensorStates = newStates
        problemTimestamps = newTimestamps
    }

    nonisolated private func sendNotification(
        sensorName: String,
        deviceName: String?,
        sensorStatus: SensorStatus,
        playSound: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Sensor \(sensorStatus.notificationLabel)"
        if let deviceName, !deviceName.isEmpty {
            content.body = "\(deviceName) › \(sensorName)"
        } else {
            content.body = sensorName
        }
        if playSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "sensor-\(sensorName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
