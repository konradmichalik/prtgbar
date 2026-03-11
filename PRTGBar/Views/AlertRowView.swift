import SwiftUI

struct AlertRowView: View {
    let item: ProblemItem
    let serverURL: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            bodyRow
        }
        .padding(.vertical, 10)
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 4) {
            if let groupName = item.groupName, !groupName.isEmpty {
                Text(groupName)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.primary.opacity(0.55))

                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(item.deviceName)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let message = item.message, SensorMessage(message).isAcknowledged {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
            }

            Spacer()

            if let downSince = item.downSince {
                let elapsed = Date().timeIntervalSince(downSince)
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 7))
                        .foregroundStyle(.quaternary)
                    Text(formatDuration(elapsed))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
    }

    // MARK: - Body

    private var bodyRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(item.status.color)
                .font(.system(size: 13))
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.sensorName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let message = item.message, !message.isEmpty {
                    Text(SensorMessage(message).text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let downSince = item.downSince {
                    let elapsed = Date().timeIntervalSince(downSince)
                    AlertDurationBar(elapsed: elapsed, color: item.status.color)
                }
            }
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .down, .partialdown:
            "exclamationmark.circle"
        case .warning, .unusual:
            "exclamationmark.triangle"
        default:
            item.status.symbolName
        }
    }
}

// MARK: - Duration Progress Bar

struct AlertDurationBar: View {
    let elapsed: TimeInterval
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let progress = durationProgress(elapsed)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.08))

                Capsule()
                    .fill(color.opacity(0.6))
                    .frame(width: max(2, progress * geo.size.width))
            }
        }
        .frame(height: 2)
        .padding(.top, 2)
    }
}

// MARK: - Duration Helpers

/// Logarithmic progress: < 1h -> 0-33%, 1-24h -> 33-66%, > 24h -> 66-100% (capped at 7d)
func durationProgress(_ seconds: TimeInterval) -> CGFloat {
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

func formatDuration(_ seconds: TimeInterval) -> String {
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
