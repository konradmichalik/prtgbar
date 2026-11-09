import AppKit

/// System label colours draw with vibrancy in menus and fade into the translucent background.
/// Fixed greys that only follow light and dark mode keep their contrast.
enum MenuColor {
    static let muted = NSColor(name: "PRTGBarMuted") { appearance in
        NSColor(white: isDark(appearance) ? 0.80 : 0.30, alpha: 1)
    }

    static let faint = NSColor(name: "PRTGBarFaint") { appearance in
        NSColor(white: isDark(appearance) ? 0.45 : 0.72, alpha: 1)
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

enum MenuGlyph {
    case down, warning, unusual, up, paused, acknowledged

    /// Colours follow the PRTG web interface.
    init(status: SensorStatus) {
        switch status {
        case .down, .partialdown: self = .down
        case .warning, .unknown: self = .warning
        case .unusual: self = .unusual
        case .paused: self = .paused
        case .up: self = .up
        }
    }

    var symbolName: String {
        switch self {
        case .down: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .unusual: "exclamationmark.circle.fill"
        case .up: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .acknowledged: "checkmark.circle"
        }
    }

    var color: NSColor {
        switch self {
        case .down: .systemRed
        case .warning: .systemYellow
        case .unusual: .systemOrange
        case .up: .systemGreen
        case .paused: .systemBlue
        case .acknowledged: MenuColor.muted
        }
    }

    /// A single palette colour would also fill the inner mark of `.fill` symbols and hide it.
    private var paletteColors: [NSColor] {
        guard symbolName.hasSuffix(".fill") else { return [color] }
        // White would vanish on yellow.
        return [self == .warning ? .black : .white, color]
    }

    var image: NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: paletteColors))
        image?.isTemplate = false
        return image
    }
}
