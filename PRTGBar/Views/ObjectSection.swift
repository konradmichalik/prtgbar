import SwiftUI

struct ObjectSection: View {
    let node: TreeNode
    let serverURL: String
    let depth: Int
    let autoExpandErrors: Bool

    @State private var isExpanded: Bool

    init(node: TreeNode, serverURL: String, depth: Int, autoExpandErrors: Bool) {
        self.node = node
        self.serverURL = serverURL
        self.depth = depth
        self.autoExpandErrors = autoExpandErrors
        // Probes and first-level groups: expanded by default
        // Groups/devices with down sensors: expanded if setting is on
        let defaultExpanded = depth < 2 || (autoExpandErrors && node.hasDownSensors)
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        switch node.kind {
        case .probedevice:
            ProbeSection(
                node: node, serverURL: serverURL,
                depth: depth, autoExpandErrors: autoExpandErrors,
                isExpanded: $isExpanded
            )
        case .group:
            GroupSection(
                node: node, serverURL: serverURL,
                depth: depth, autoExpandErrors: autoExpandErrors,
                isExpanded: $isExpanded
            )
        case .device:
            DeviceSection(
                node: node, serverURL: serverURL,
                depth: depth, autoExpandErrors: autoExpandErrors,
                isExpanded: $isExpanded
            )
        case .sensor:
            SensorRow(node: node, serverURL: serverURL)
        }
    }
}

// MARK: - Probe

private struct ProbeSection: View {
    let node: TreeNode
    let serverURL: String
    let depth: Int
    let autoExpandErrors: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(node.children) { child in
                ObjectSection(
                    node: child, serverURL: serverURL,
                    depth: depth + 1, autoExpandErrors: autoExpandErrors
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .foregroundStyle(node.worstStatus.color)
                    .font(.caption)
                Text(node.name)
                    .font(.body.bold())
                    .lineLimit(1)
            }
        }
        .contextMenu { objectContextMenu(node: node, serverURL: serverURL) }
    }
}

// MARK: - Group

private struct GroupSection: View {
    let node: TreeNode
    let serverURL: String
    let depth: Int
    let autoExpandErrors: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(node.children) { child in
                ObjectSection(
                    node: child, serverURL: serverURL,
                    depth: depth + 1, autoExpandErrors: autoExpandErrors
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: depth <= 2 ? "folder.fill" : "folder")
                    .foregroundStyle(node.worstStatus.color)
                    .font(.caption)
                Text(node.name)
                    .font(depth <= 2 ? .body.weight(.semibold) : .subheadline)
                    .lineLimit(1)
                Spacer()
                if !isExpanded {
                    Text("\(node.totalSensorCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .contextMenu { objectContextMenu(node: node, serverURL: serverURL) }
    }
}

// MARK: - Device

private struct DeviceSection: View {
    let node: TreeNode
    let serverURL: String
    let depth: Int
    let autoExpandErrors: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(node.children) { child in
                ObjectSection(
                    node: child, serverURL: serverURL,
                    depth: depth + 1, autoExpandErrors: autoExpandErrors
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(node.worstStatus.color)
                    .font(.caption)
                Text(node.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if !isExpanded, let summary = node.statusSummary {
                    MiniSummary(summary: summary)
                }
            }
        }
        .contextMenu { objectContextMenu(node: node, serverURL: serverURL) }
    }
}

// MARK: - Sensor Row

private struct SensorRow: View {
    let node: TreeNode
    let serverURL: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.status.symbolName)
                .foregroundStyle(node.status.color)
                .font(.caption2)

            Text(node.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let message = node.message, !message.isEmpty {
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
        .padding(.vertical, 1)
        .contextMenu { sensorContextMenu(node: node, serverURL: serverURL) }
    }
}

// MARK: - Mini Summary

private struct MiniSummary: View {
    let summary: StatusSummary

    var body: some View {
        HStack(spacing: 4) {
            if summary.up > 0 {
                miniDot(count: summary.up, color: .green)
            }
            if summary.down > 0 {
                miniDot(count: summary.down, color: .red)
            }
            if summary.warning > 0 {
                miniDot(count: summary.warning, color: .yellow)
            }
        }
    }

    private func miniDot(count: Int, color: Color) -> some View {
        HStack(spacing: 1) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            Text("\(count)")
                .font(.system(size: 9).monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Context Menus

private func objectContextMenu(node: TreeNode, serverURL: String) -> some View {
    Group {
        Button("Open in PRTG") {
            openInPrtg(objectId: node.id, serverURL: serverURL)
        }
        Divider()
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.name, forType: .string)
        }
        Button("Copy ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(node.id)", forType: .string)
        }
    }
}

private func sensorContextMenu(node: TreeNode, serverURL: String) -> some View {
    Group {
        Button("Open in PRTG") {
            openInPrtg(objectId: node.id, serverURL: serverURL)
        }
        Divider()
        Button("Copy Sensor Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.name, forType: .string)
        }
        Button("Copy Sensor ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(node.id)", forType: .string)
        }
    }
}

func openInPrtg(objectId: Int, serverURL: String) {
    let base = serverURL
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

    guard var components = URLComponents(string: base) else { return }
    // Web UI runs on default port (443), not the API port
    components.port = nil
    components.path = "/sensor.htm"
    components.queryItems = [URLQueryItem(name: "id", value: "\(objectId)")]

    guard let url = components.url else { return }
    NSWorkspace.shared.open(url)
}
