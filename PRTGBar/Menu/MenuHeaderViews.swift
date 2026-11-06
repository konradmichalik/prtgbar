import AppKit
import SwiftUI

enum MenuLayout {
    static let headerWidth: CGFloat = 340
    static let detailWidth: CGFloat = 300
}

// MARK: - Summary

struct SummaryHeaderView: View {
    let host: String
    let summary: StatusSummary
    let hasData: Bool

    private var isAllUp: Bool { hasData && summary.down == 0 && summary.warning == 0 }

    var body: some View {
        HStack(spacing: 10) {
            if isAllUp {
                Image(systemName: MenuGlyph.up.symbolName)
                    .font(.system(size: 28))
                    .foregroundStyle(Color(nsColor: MenuGlyph.up.color))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("PRTG").font(.headline)
                    Text(host).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                summaryLine.font(.callout)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: MenuLayout.headerWidth, alignment: .leading)
    }

    private var summaryLine: Text {
        guard hasData else { return Text("Waiting for data…").foregroundColor(.secondary) }
        if isAllUp {
            let count = summary.up.formatted(.number.locale(Locale(identifier: "en_US")))
            return Text("All \(count) sensors up").foregroundColor(.secondary)
        }
        let parts = MenuText.summaryLine(summary).components(separatedBy: " · ").map(glyphPart)
        return parts.dropFirst().reduce(parts.first ?? Text("")) { line, part in
            line + Text(" · ").foregroundColor(.secondary) + part
        }
    }

    private func glyphPart(_ part: String) -> Text {
        let glyph: MenuGlyph = part.hasSuffix("Down") ? .down : (part.hasSuffix("Warning") ? .warning : .up)
        return Text(Image(systemName: glyph.symbolName)).foregroundColor(Color(nsColor: glyph.color))
            + Text(" \(part)")
    }
}

// MARK: - Project

struct ProjectHeaderView: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: MenuLayout.detailWidth, alignment: .leading)
    }
}

// MARK: - Sensor Detail

struct SensorDetailHeaderView: View {
    let name: String
    let statusLine: String
    let statusColor: NSColor
    let message: String?
    let history: HistorySummary?
    let breadcrumb: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline).lineLimit(2)
            Text(statusLine).font(.callout).foregroundStyle(Color(nsColor: statusColor))
            if let message, !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            if let history {
                UptimeStripView(segments: history.segments).padding(.top, 2)
                Text(Self.historyLine(history)).font(.caption).foregroundStyle(.secondary)
            }
            Text(breadcrumb).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: MenuLayout.detailWidth, alignment: .leading)
    }

    static func historyLine(_ history: HistorySummary) -> String {
        guard let ratio = history.upRatio else { return "No history recorded yet" }
        let outages = history.outageCount == 1 ? "1 outage" : "\(history.outageCount) outages"
        return "\(Int((ratio * 100).rounded(.down)))% up · \(outages)"
    }
}

struct UptimeStripView: View {
    let segments: [SegmentState]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(for: segment))
                    .frame(maxWidth: .infinity)
                    .frame(height: segment == .down ? 12 : 6)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func color(for segment: SegmentState) -> Color {
        switch segment {
        case .up: Color(nsColor: MenuGlyph.up.color)
        case .down: Color(nsColor: MenuGlyph.down.color)
        case .noData: Color(nsColor: .quaternaryLabelColor)
        }
    }
}
