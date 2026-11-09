import AppKit

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
        case .acknowledged: .secondaryLabelColor
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
