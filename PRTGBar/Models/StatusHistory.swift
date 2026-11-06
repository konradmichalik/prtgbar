import Foundation

enum SegmentState: Equatable {
    case up, down, noData
}

struct HistorySummary: Equatable {
    let segments: [SegmentState]
    let upRatio: Double?
    let outageCount: Int
}

@MainActor
final class StatusHistory {
    static let segmentCount = 48
    static let segmentLength: TimeInterval = 1800
    private static let window = TimeInterval(segmentCount) * segmentLength

    private struct Observation: Codable {
        let t: Double
        let d: Bool
    }

    private let fileURL: URL?
    private var observations: [Int: [Observation]] = [:]

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PRTGBar", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    func record(_ states: [Int: SensorStatus], at date: Date) {
        let time = date.timeIntervalSince1970
        for (id, status) in states {
            let isDown = status == .down || status == .partialdown
            observations[id, default: []].append(Observation(t: time, d: isDown))
        }
        prune(now: date)
    }

    func summary(for sensorId: Int, now: Date) -> HistorySummary {
        let nowTime = now.timeIntervalSince1970
        var hasUp = [Bool](repeating: false, count: Self.segmentCount)
        var hasDown = [Bool](repeating: false, count: Self.segmentCount)

        for observation in observations[sensorId] ?? [] {
            let age = nowTime - observation.t
            guard age >= 0, age <= Self.window else { continue }
            // Segments are start-inclusive and end-exclusive, the newest one also includes `now`.
            let slotsAgo = max(1, Int((age / Self.segmentLength).rounded(.up)))
            let index = Self.segmentCount - slotsAgo
            if observation.d { hasDown[index] = true } else { hasUp[index] = true }
        }

        let segments: [SegmentState] = (0..<Self.segmentCount).map { i in
            hasDown[i] ? .down : (hasUp[i] ? .up : .noData)
        }
        return HistorySummary(
            segments: segments,
            upRatio: Self.upRatio(of: segments),
            outageCount: Self.outageCount(of: segments)
        )
    }

    func save() throws {
        guard let fileURL else { return }
        let stored = Dictionary(uniqueKeysWithValues: observations.map { (String($0.key), $0.value) })
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
    }

    func observationCount(for sensorId: Int) -> Int {
        observations[sensorId]?.count ?? 0
    }

    func load(now: Date = Date()) throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stored = try JSONDecoder().decode([String: [Observation]].self, from: Data(contentsOf: fileURL))
        // "1" and "01" parse to the same id, so merge instead of trapping on duplicates.
        observations = Dictionary(
            stored.compactMap { key, value in Int(key).map { ($0, value) } },
            uniquingKeysWith: { $0 + $1 }
        )
        prune(now: now)
    }

    private func prune(now: Date) {
        let cutoff = now.timeIntervalSince1970 - Self.window
        observations = observations.compactMapValues { list in
            let kept = list.filter { $0.t >= cutoff }
            return kept.isEmpty ? nil : kept
        }
    }

    private static func upRatio(of segments: [SegmentState]) -> Double? {
        let up = segments.filter { $0 == .up }.count
        let down = segments.filter { $0 == .down }.count
        return up + down == 0 ? nil : Double(up) / Double(up + down)
    }

    private static func outageCount(of segments: [SegmentState]) -> Int {
        var count = 0
        var previous: SegmentState = .noData
        for segment in segments {
            if segment == .down && previous != .down { count += 1 }
            previous = segment
        }
        return count
    }
}
