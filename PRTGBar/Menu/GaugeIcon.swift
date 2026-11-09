import AppKit

enum GaugeLevel: Equatable {
    case ok, warning, down

    init(_ summary: StatusSummary) {
        if summary.down > 0 {
            self = .down
        } else if summary.warning > 0 || summary.unusual > 0 {
            self = .warning
        } else {
            self = .ok
        }
    }
}

/// The PRTG gauge, drawn so the needle can point at the current state.
enum GaugeIcon {
    enum Style {
        /// Monochrome menu bar template.
        case template
        /// Label colour, with only the segment of the current level in its status colour.
        case accented
        /// The app icon colours on a white tile.
        case logo
    }

    private struct Segment {
        let from: CGFloat
        let to: CGFloat
        let color: NSColor
    }

    // Degrees, counterclockwise from 3 o'clock. The open side faces down like the PRTG logo.
    private static let scaleStart: CGFloat = 215
    private static let scaleEnd: CGFloat = -35

    private static let green = NSColor(srgbRed: 0.71, green: 0.80, blue: 0.23, alpha: 1)
    private static let orange = NSColor(srgbRed: 0.97, green: 0.63, blue: 0.13, alpha: 1)
    private static let pink = NSColor(srgbRed: 0.91, green: 0.06, blue: 0.42, alpha: 1)
    private static let navy = NSColor(srgbRed: 0, green: 0.22, blue: 0.52, alpha: 1)

    static func needleAngle(for level: GaugeLevel) -> CGFloat {
        switch level {
        case .ok: 165
        case .warning: 90
        case .down: 15
        }
    }

    /// Drawn on demand, so dynamic colours follow the menu bar appearance.
    static func image(size: NSSize, level: GaugeLevel, style: Style) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            if case .logo = style {
                drawTile(in: rect)
                draw(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12), level: level, style: style)
            } else {
                draw(in: rect, level: level, style: style)
            }
            return true
        }
        if case .template = style { image.isTemplate = true }
        return image
    }

    // MARK: - Private

    private static func drawTile(in rect: NSRect) {
        let radius = rect.width * 0.225
        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        tile.fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        tile.lineWidth = 1
        tile.stroke()
    }

    private static func draw(in rect: NSRect, level: GaugeLevel, style: Style) {
        let center = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.42)
        let lineWidth = rect.width * 0.15
        let radius = rect.width / 2 - lineWidth / 2
        for segment in segments(for: style, level: level) {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: segment.from, endAngle: segment.to, clockwise: true)
            arc.lineWidth = lineWidth
            segment.color.setStroke()
            arc.stroke()
        }
        needleColor(for: style).setFill()
        needle(center: center, length: radius * 0.72, width: lineWidth * 0.55, angle: needleAngle(for: level)).fill()
    }

    private static func segments(for style: Style, level: GaugeLevel) -> [Segment] {
        switch style {
        case .template:
            return scale(.black, .black, .black)
        case .logo:
            return scale(green, orange, pink)
        case .accented:
            return scale(
                .labelColor,
                level == .warning ? .systemOrange : .labelColor,
                level == .down ? .systemRed : .labelColor
            )
        }
    }

    /// Same three segments in every style, so the icon keeps its shape when the state changes.
    private static func scale(_ ok: NSColor, _ warning: NSColor, _ down: NSColor) -> [Segment] {
        [
            Segment(from: scaleStart, to: 148, color: ok),
            Segment(from: 144, to: 40, color: warning),
            Segment(from: 36, to: scaleEnd, color: down),
        ]
    }

    private static func needleColor(for style: Style) -> NSColor {
        switch style {
        case .template: .black
        case .accented: .labelColor
        case .logo: navy
        }
    }

    private static func needle(center: NSPoint, length: CGFloat, width: CGFloat, angle degrees: CGFloat) -> NSBezierPath {
        let angle = degrees * .pi / 180
        let across = angle + .pi / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
        path.line(to: NSPoint(x: center.x + cos(across) * width / 2, y: center.y + sin(across) * width / 2))
        path.line(to: NSPoint(x: center.x - cos(across) * width / 2, y: center.y - sin(across) * width / 2))
        path.close()
        return path
    }
}
