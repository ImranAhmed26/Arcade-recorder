import SwiftUI
import AppKit

/// Central design tokens. Re-brand the whole app by editing `primary` / `secondary`.
/// All brand colors adapt to light/dark automatically via a dynamic NSColor provider,
/// and surfaces use semantic system colors so light mode stays white and airy.
/// User-selectable appearance. `system` follows macOS; the others force it.
enum ThemeMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Theme {

    // MARK: - Brand (the only custom colors — swap these to re-theme)

    /// Emerald. Light = oklch(50.8% 0.118 165.612), dark = oklch(69.6% 0.17 162.48).
    static let primary = dynamic(light: 0x007A55, dark: 0x00BC7D)
    /// Pine / teal supporting accent.
    static let secondary = dynamic(light: 0x0B7E74, dark: 0x29C2B3)
    /// Record actions are always red — oklch(63.7% 0.237 25.331).
    static let record = Color(nsColor: NSColor(hex: 0xFB2C36))

    /// A soft tint of the primary, for chips / selected backgrounds.
    static var primaryTint: Color { primary.opacity(0.12) }

    // MARK: - Surfaces (semantic → automatic light/dark)

    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let fieldBackground = Color(nsColor: .textBackgroundColor)

    // MARK: - Layout tokens

    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 8
        static let pill: CGFloat = 999
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Helpers

    /// A color that resolves differently in light vs dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension View {
    /// Standard card chrome: rounded surface, hairline border, soft shadow.
    func cardSurface(padding: CGFloat = Theme.Space.lg) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
