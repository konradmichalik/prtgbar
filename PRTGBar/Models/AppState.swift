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

    var badgeCount: Int? {
        guard showBadgeCount else { return nil }
        let count = treeNodes.reduce(0) { total, node in
            total + countDown(node)
        }
        return count > 0 ? count : nil
    }

    var statusCounts: StatusSummary {
        treeNodes.reduce(into: StatusSummary.empty) { result, node in
            result += countSensors(node)
        }
    }

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
        if DemoData.isEnabled {
            loadDemoData()
            return
        }
        if notifyOnStatusChange {
            requestNotificationPermission()
        }
        startPolling()
    }

    private func loadDemoData() {
        treeNodes = DemoData.buildTree()
        problemTimestamps = DemoData.problemTimestamps
        lastUpdated = Date()
        isConfigured = true
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

    // MARK: - Acknowledge

    func acknowledgeAlarm(objectId: Int) async {
        do {
            try await Task.detached { [serverURL, apiKey, acceptSelfSignedCerts] in
                try await PrtgClient.acknowledgeAlarm(
                    objectId: objectId,
                    serverURL: serverURL, token: apiKey, acceptSelfSignedCerts: acceptSelfSignedCerts
                )
            }.value
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
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

    // MARK: - Helpers

    private func isAcknowledged(_ node: TreeNode) -> Bool {
        node.message.map { SensorMessage($0).isAcknowledged } ?? false
    }

    private func countDown(_ node: TreeNode) -> Int {
        if node.kind == .sensor, node.status == .down {
            if !showAcknowledged, isAcknowledged(node) { return 0 }
            return 1
        }
        return node.children.reduce(0) { $0 + countDown($1) }
    }

    private func countSensors(_ node: TreeNode) -> StatusSummary {
        var result = StatusSummary.empty
        if node.kind == .sensor {
            if !showAcknowledged, isAcknowledged(node), SensorStatus.problemStatuses.contains(node.status) {
                return result
            }
            switch node.status {
            case .up: result = StatusSummary(up: 1, down: 0, warning: 0, paused: 0, unknown: 0)
            case .down: result = StatusSummary(up: 0, down: 1, warning: 0, paused: 0, unknown: 0)
            case .warning: result = StatusSummary(up: 0, down: 0, warning: 1, paused: 0, unknown: 0)
            case .paused: result = StatusSummary(up: 0, down: 0, warning: 0, paused: 1, unknown: 0)
            default: result = StatusSummary(up: 0, down: 0, warning: 0, paused: 0, unknown: 1)
            }
        }
        return node.children.reduce(into: result) { acc, child in
            acc += countSensors(child)
        }
    }
}
