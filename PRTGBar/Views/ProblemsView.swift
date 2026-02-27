import SwiftUI

struct ProblemsView: View {
    let treeNodes: [TreeNode]
    let statusCounts: StatusSummary
    let serverURL: String
    let problemTimestamps: [Int: Date]

    var body: some View {
        let problems = ProblemItem.collect(from: treeNodes, fallbackTimestamps: problemTimestamps)
        if problems.isEmpty {
            allGoodView
        } else {
            let down = problems.filter { $0.status == .down || $0.status == .partialdown }
            let warnings = problems.filter { $0.status != .down && $0.status != .partialdown }
            problemsList(down: down, warnings: warnings)
        }
    }

    // MARK: - All Good

    private var allGoodView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("All \(statusCounts.total) sensors up")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Problems List

    private func problemsList(down: [ProblemItem], warnings: [ProblemItem]) -> some View {
        List {
            if !down.isEmpty {
                Section {
                    ForEach(down) { item in
                        ProblemRow(item: item, serverURL: serverURL)
                    }
                } header: {
                    sectionHeader(
                        count: down.count,
                        label: "Down",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                }
            }

            if !warnings.isEmpty {
                Section {
                    ForEach(warnings) { item in
                        ProblemRow(item: item, serverURL: serverURL)
                    }
                } header: {
                    sectionHeader(
                        count: warnings.count,
                        label: warnings.count == 1 ? "Warning" : "Warnings",
                        icon: "exclamationmark.triangle.fill",
                        color: .yellow
                    )
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    // MARK: - Components

    private func sectionHeader(
        count: Int, label: String, icon: String, color: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count) \(label)")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
    }

}

// MARK: - Problem Row

private struct ProblemRow: View {
    let item: ProblemItem
    let serverURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: item.status.symbolName)
                    .foregroundStyle(item.status.color)
                    .font(.caption2)

                Text(item.sensorName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let message = item.message, !message.isEmpty {
                    let parsed = SensorMessage(message)
                    if parsed.isAcknowledged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7))
                            .foregroundStyle(.green)
                    }
                    Text(parsed.text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 0) {
                if !item.breadcrumb.isEmpty {
                    Text(item.breadcrumb)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.leading, 18)
                }

                Spacer()

                if let downSince = item.downSince {
                    let elapsed = Date().timeIntervalSince(downSince)
                    Text(formatDuration(elapsed))
                        .font(.caption2.monospaced())
                        .foregroundStyle(durationColor(elapsed))
                        .lineLimit(1)
                }
            }

            if let elapsed = item.downSince.map({ Date().timeIntervalSince($0) }), elapsed > 0 {
                DurationBar(elapsed: elapsed, status: item.status)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Open in PRTG") {
                openInPrtg(objectId: item.id, serverURL: serverURL)
            }
            Divider()
            Button("Copy Sensor Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.sensorName, forType: .string)
            }
            Button("Copy Sensor ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(item.id)", forType: .string)
            }
        }
    }
}

// MARK: - Duration Bar

private struct DurationBar: View {
    let elapsed: TimeInterval
    let status: SensorStatus

    var body: some View {
        GeometryReader { geo in
            let progress = durationProgress(elapsed)
            let color = durationColor(elapsed)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.5), color.opacity(0.15)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(2, progress * geo.size.width))
        }
        .frame(height: 2)
    }
}

// MARK: - Duration Helpers

/// Logarithmic progress: < 1h → 0–33%, 1–24h → 33–66%, > 24h → 66–100% (capped at 7d)
private func durationProgress(_ seconds: TimeInterval) -> CGFloat {
    guard seconds > 0 else { return 0 }
    let hours = seconds / 3600

    if hours < 1 {
        return CGFloat(hours) * 0.33
    } else if hours < 24 {
        return 0.33 + CGFloat((hours - 1) / 23) * 0.33
    } else {
        let days = hours / 24
        return min(1.0, 0.66 + CGFloat((days - 1) / 6) * 0.34)
    }
}

private func durationColor(_ seconds: TimeInterval) -> Color {
    let hours = seconds / 3600
    if hours < 1 { return .yellow }
    if hours < 24 { return .orange }
    return .red
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    guard s > 0 else { return "" }

    let minutes = s / 60
    let hours = minutes / 60
    let days = hours / 24

    if minutes < 1 { return "< 1m" }
    if hours < 1 { return "\(minutes)m" }
    if days < 1 { return "\(hours)h \(minutes % 60)m" }
    if days < 7 { return "\(days)d \(hours % 24)h" }
    return "\(days)d"
}
