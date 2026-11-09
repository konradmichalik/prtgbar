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
    @ObservedObject var activity: RefreshActivity
    let openServer: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: GaugeIcon.image(
                size: NSSize(width: 32, height: 32),
                level: hasData ? GaugeLevel(summary) : .ok,
                style: .logo
            ))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    (Text("PRTG").font(.headline) + Text("bar").font(.caption).baselineOffset(6))
                    Spacer(minLength: 8)
                    Button(action: openServer) {
                        Text(host).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open PRTG")
                }
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if activity.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Refreshing")
                    }
                    summaryLine.font(.callout)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minWidth: MenuLayout.headerWidth, maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLine: Text {
        guard hasData else { return Text("Loading…").foregroundColor(.secondary) }
        return StatusSummaryText.make(summary)
    }
}

// MARK: - Status Summary

/// "▲ 8 Warning · ✓ 26 Up" with status glyphs, shared by the main and the project header.
enum StatusSummaryText {
    static func make(_ summary: StatusSummary) -> Text {
        if summary.down == 0, summary.warning == 0, summary.unusual == 0, summary.paused == 0 {
            return glyphPart(.up, "All \(MenuText.count(summary.up, "sensor")) up")
        }
        let parts = MenuText.summaryParts(summary).map { glyphPart($0.glyph, $0.text) }
        return parts.dropFirst().reduce(parts.first ?? Text("")) { line, part in
            line + Text(" · ").foregroundColor(.secondary) + part
        }
    }

    private static func glyphPart(_ glyph: MenuGlyph, _ text: String) -> Text {
        Text(Image(systemName: glyph.symbolName)).foregroundColor(Color(nsColor: glyph.color)) + Text(" \(text)")
    }
}

// MARK: - Device Line

struct PathLineView: View {
    let text: String
    let emphasized: Bool

    var body: some View {
        Text(text)
            .fontWeight(emphasized ? .semibold : .regular)
            .foregroundStyle(emphasized ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 1)
            .frame(width: MenuLayout.headerWidth, alignment: .leading)
    }
}

// MARK: - Project

struct ProjectHeaderView: View {
    let name: String
    let summary: StatusSummary
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
            StatusSummaryText.make(summary).font(.callout)
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
    let lastValue: String?
    let history: HistorySummary?
    let breadcrumb: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline).lineLimit(2)
            Text(statusLine).font(.callout).foregroundStyle(Color(nsColor: statusColor))
            if let message, !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            if let lastValue, !lastValue.isEmpty {
                Text("Last value: \(lastValue)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
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
        return "\(Int((ratio * 100).rounded(.down)))% up · \(MenuText.count(history.outageCount, "outage"))"
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
        case .warning: Color(nsColor: MenuGlyph.warning.color)
        case .unusual: Color(nsColor: MenuGlyph.unusual.color)
        case .paused: Color(nsColor: MenuGlyph.paused.color)
        case .down: Color(nsColor: MenuGlyph.down.color)
        case .noData: Color(nsColor: .quaternaryLabelColor)
        }
    }
}
