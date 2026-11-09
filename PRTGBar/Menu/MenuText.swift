import AppKit

enum MenuText {
    static func muted(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0), .foregroundColor: MenuColor.muted,
        ])
    }

    /// Keeps head and tail so hostnames stay recognisable; the head gets the extra character when odd.
    static func truncated(_ s: String, max: Int = 48) -> String {
        guard s.count > max, max > 1 else { return s }
        let keep = max - 1
        let head = (keep + 1) / 2
        let tail = keep - head
        return String(s.prefix(head)) + "…" + String(s.suffix(tail))
    }

    static func updatedAgo(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<10: return "Updated just now"
        case ..<60: return "Updated \(seconds) s ago"
        case ..<3600: return "Updated \(seconds / 60) min ago"
        default: return "Updated \(seconds / 3600) h ago"
        }
    }

    static func summaryParts(_ s: StatusSummary) -> [(glyph: MenuGlyph, text: String)] {
        var parts: [(glyph: MenuGlyph, text: String)] = []
        if s.down > 0 { parts.append((.down, "\(s.down) Down")) }
        if s.warning > 0 { parts.append((.warning, "\(s.warning) Warning")) }
        if s.unusual > 0 { parts.append((.unusual, "\(s.unusual) Unusual")) }
        if s.paused > 0 { parts.append((.paused, "\(grouped(s.paused)) Paused")) }
        parts.append((.up, "\(grouped(s.up)) Up"))
        return parts
    }

    static func summaryLine(_ s: StatusSummary) -> String {
        summaryParts(s).map(\.text).joined(separator: " · ")
    }

    static func count(_ n: Int, _ noun: String) -> String {
        "\(grouped(n)) \(noun)\(n == 1 ? "" : "s")"
    }

    private static func grouped(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: n)) ?? String(n)
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
