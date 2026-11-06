import Foundation
import os

enum SegmentState: Equatable {
    case up, down, noData
}

struct HistorySummary: Equatable {
    let segments: [SegmentState]
    let upRatio: Double?
    let outageCount: Int
}

extension Logger {
    static let history = Logger(subsystem: "com.konradmichalik.prtgbar", category: "history")
}

@MainActor
final class StatusHistory {
    static let segmentCount = 48
    static let segmentLength: TimeInterval = 1800
    private static let window = TimeInterval(segmentCount) * segmentLength

    /// Stored as one integer per slot to keep the file small with thousands of sensors.
    private struct SlotFlags: Codable {
        var hasUp = false
        var hasDown = false

        init() {}

        init(from decoder: Decoder) throws {
            let bits = try decoder.singleValueContainer().decode(Int.self)
            hasUp = bits & 1 != 0
            hasDown = bits & 2 != 0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode((hasUp ? 1 : 0) | (hasDown ? 2 : 0))
        }

        mutating func add(isDown: Bool) {
            if isDown { hasDown = true } else { hasUp = true }
        }

        func merged(with other: SlotFlags) -> SlotFlags {
            var result = self
            result.hasUp = hasUp || other.hasUp
            result.hasDown = hasDown || other.hasDown
            return result
        }
    }

    /// Sensor id → slot start (seconds since 1970, a multiple of `segmentLength`) → flags.
    private typealias Slots = [Int: [Int: SlotFlags]]

    private let fileURL: URL?
    private var slots: Slots = [:]
    private var lastPruneKey: Int?
    private var lastSaveSlot: Int?

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
        let slot = Self.slotStart(of: date)
        for (id, status) in states {
            slots[id, default: [:]][slot, default: SlotFlags()].add(isDown: status == .down || status == .partialdown)
        }
        prune(now: date)
    }

    func summary(for sensorId: Int, now: Date) -> HistorySummary {
        let nowTime = now.timeIntervalSince1970
        var hasUp = [Bool](repeating: false, count: Self.segmentCount)
        var hasDown = [Bool](repeating: false, count: Self.segmentCount)

        for (slot, flags) in slots[sensorId] ?? [:] {
            let age = nowTime - TimeInterval(slot)
            guard age >= 0, age <= Self.window else { continue }
            // Segments are start-inclusive and end-exclusive, the newest one also includes `now`.
            let slotsAgo = max(1, Int((age / Self.segmentLength).rounded(.up)))
            let index = Self.segmentCount - slotsAgo
            if flags.hasDown { hasDown[index] = true }
            if flags.hasUp { hasUp[index] = true }
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

    func slotCount(for sensorId: Int) -> Int {
        slots[sensorId]?.count ?? 0
    }

    func removeAll() {
        slots = [:]
        lastPruneKey = nil
        lastSaveSlot = nil
    }

    // MARK: - Persistence

    /// Writes synchronously; meant for app termination, when a background write could be cut off.
    func save() throws {
        guard let fileURL else { return }
        try Self.write(slots, to: fileURL)
    }

    /// Writes at most once per slot, encoding a snapshot off the main actor.
    @discardableResult
    func saveIfNeeded(now: Date) -> Bool {
        let slot = Self.slotStart(of: now)
        guard slot != lastSaveSlot else { return false }
        lastSaveSlot = slot
        guard let fileURL else { return true }
        let snapshot = slots
        Task.detached(priority: .utility) {
            do {
                try Self.write(snapshot, to: fileURL)
            } catch {
                Logger.history.error("Saving status history failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    func load(now: Date = Date()) throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stored = try JSONDecoder().decode([String: [String: SlotFlags]].self, from: Data(contentsOf: fileURL))
        // "1" and "01" parse to the same id, so merge instead of trapping on duplicates.
        slots = Dictionary(
            stored.compactMap { key, value in Int(key).map { ($0, Self.parseSlots(value)) } },
            uniquingKeysWith: { first, second in first.merging(second) { $0.merged(with: $1) } }
        )
        lastPruneKey = nil
        prune(now: now)
    }

    nonisolated private static func write(_ slots: Slots, to fileURL: URL) throws {
        let stored = Dictionary(uniqueKeysWithValues: slots.map { id, sensorSlots in
            (String(id), Dictionary(uniqueKeysWithValues: sensorSlots.map { (String($0.key), $0.value) }))
        })
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
    }

    private static func parseSlots(_ stored: [String: SlotFlags]) -> [Int: SlotFlags] {
        Dictionary(
            stored.compactMap { key, value in Int(key).map { ($0, value) } },
            uniquingKeysWith: { $0.merged(with: $1) }
        )
    }

    // MARK: - Private

    private static func slotStart(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / segmentLength).rounded(.down)) * Int(segmentLength)
    }

    /// Slot starts are multiples of the segment length, so the kept set only changes when the
    /// cutoff crosses one; pruning every poll would walk every stored slot for nothing.
    private func prune(now: Date) {
        let cutoff = now.timeIntervalSince1970 - Self.window
        let key = Int((cutoff / Self.segmentLength).rounded(.up))
        guard key != lastPruneKey else { return }
        lastPruneKey = key
        slots = slots.compactMapValues { sensorSlots in
            let kept = sensorSlots.filter { TimeInterval($0.key) >= cutoff }
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
