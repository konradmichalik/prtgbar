import SwiftUI

struct ProblemsView: View {
    let treeNodes: [TreeNode]
    let statusCounts: StatusSummary
    let serverURL: String
    let onShowAllSensors: () -> Void

    var body: some View {
        let problems = ProblemItem.collect(from: treeNodes)
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
            showAllButton
                .padding(.bottom, 12)
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

            Section {
                showAllButton
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

    private var showAllButton: some View {
        Button(action: onShowAllSensors) {
            HStack {
                Text("Show all \(statusCounts.total) sensors")
                    .font(.caption)
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
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
                    Text(message)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !item.breadcrumb.isEmpty {
                Text(item.breadcrumb)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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
