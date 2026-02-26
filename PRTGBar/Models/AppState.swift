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
        let count = treeNodes.reduce(0) { total, node in
            total + countDown(node)
        }
        return count > 0 ? count : nil
    }

    var statusCounts: StatusSummary {
        var up = 0, down = 0, warning = 0, paused = 0, unknown = 0
        for node in treeNodes {
            accumulateCounts(node, up: &up, down: &down, warning: &warning, paused: &paused, unknown: &unknown)
        }
        return StatusSummary(up: up, down: down, warning: warning, paused: paused, unknown: unknown)
    }

    // MARK: - Settings (persisted)

    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("refreshInterval") var refreshInterval: Double = 60
    @AppStorage("autoExpandErrors") var autoExpandErrors = true
    @AppStorage("notifyOnStatusChange") var notifyOnStatusChange = true

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

    // MARK: - Polling

    private var timerCancellable: AnyCancellable?
    private var previousSensorStates: [Int: SensorStatus] = [:]

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
            let objects = try await Task.detached { [serverURL, apiKey] in
                try await PrtgClient.fetchObjects(serverURL: serverURL, token: apiKey)
            }.value

            let tree = TreeBuilder.buildTree(from: objects)

            if notifyOnStatusChange {
                detectStatusChanges(objects: objects)
            }

            treeNodes = tree
            lastUpdated = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    func testConnection() async -> Bool {
        do {
            return try await Task.detached { [serverURL, apiKey] in
                try await PrtgClient.testConnection(serverURL: serverURL, token: apiKey)
            }.value
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func detectStatusChanges(objects: [PrtgObject]) {
        let sensors = objects.filter { $0.kind == .sensor }
        var newStates: [Int: SensorStatus] = [:]

        for sensor in sensors {
            guard let status = sensor.status else { continue }
            newStates[sensor.id] = status

            if let previousStatus = previousSensorStates[sensor.id],
               previousStatus != .down, status == .down {
                sendNotification(sensorName: sensor.name, status: "down")
            }
        }

        previousSensorStates = newStates
    }

    private nonisolated func sendNotification(sensorName: String, status: String) {
        let content = UNMutableNotificationContent()
        content.title = "Sensor Down"
        content.body = "\(sensorName) is now \(status)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sensor-\(sensorName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func countDown(_ node: TreeNode) -> Int {
        if node.kind == .sensor, node.status == .down { return 1 }
        return node.children.reduce(0) { $0 + countDown($1) }
    }

    private func accumulateCounts(
        _ node: TreeNode,
        up: inout Int, down: inout Int, warning: inout Int, paused: inout Int, unknown: inout Int
    ) {
        if node.kind == .sensor {
            switch node.status {
            case .up: up += 1
            case .down: down += 1
            case .warning: warning += 1
            case .paused: paused += 1
            default: unknown += 1
            }
        }
        for child in node.children {
            accumulateCounts(child, up: &up, down: &down, warning: &warning, paused: &paused, unknown: &unknown)
        }
    }
}
