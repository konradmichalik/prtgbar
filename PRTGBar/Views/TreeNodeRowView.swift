import SwiftUI

struct TreeNodeRowView: View {
    let node: TreeNode
    let serverURL: String
    let searchActive: Bool
    var depth: Int = 0

    @EnvironmentObject private var appState: AppState
    @State private var isExpanded = false

    private var indent: CGFloat { CGFloat(depth) * 16 }

    var body: some View {
        if node.kind == .sensor {
            sensorRow
        } else {
            containerRow
        }
    }

    // MARK: - Container (Probe / Group / Device)

    private var containerRow: some View {
        DisclosureGroup(isExpanded: expandedBinding) {
            ForEach(node.children) { child in
                TreeNodeRowView(node: child, serverURL: serverURL, searchActive: searchActive, depth: depth + 1)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: node.worstStatus.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(node.worstStatus.color)
                    .frame(width: 14)

                Text(node.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(node.totalSensorCount)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.primary.opacity(0.05)))
            }
            .contextMenu { nodeContextMenu }
        }
        .padding(.leading, indent)
    }

    private var expandedBinding: Binding<Bool> {
        if searchActive {
            return .constant(true)
        }
        return $isExpanded
    }

    // MARK: - Sensor (Leaf)

    private var sensorRow: some View {
        HStack(spacing: 6) {
            Image(systemName: node.status.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(node.status.color)
                .frame(width: 14)

            Text(node.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let message = node.message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .trailing)
            }
        }
        .padding(.vertical, 1)
        .padding(.leading, indent)
        .contextMenu { nodeContextMenu }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var nodeContextMenu: some View {
        Button("Open in PRTG") {
            openInPrtg(objectId: node.id, serverURL: serverURL)
        }
        Divider()
        if node.kind == .sensor, SensorStatus.problemStatuses.contains(node.status) {
            let isAcknowledged = node.message.map { SensorMessage($0).isAcknowledged } ?? false
            if !isAcknowledged {
                Button("Acknowledge") {
                    Task { await appState.acknowledgeAlarm(objectId: node.id) }
                }
                Divider()
            }
        }
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
