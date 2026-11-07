import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Warm, soft Skylight-inspired palette.
enum Palette {
    static let canvas = Color(light: 0xFBF7F2, dark: 0x16140F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x221F1A)
    static let sidebar = Color(light: 0xF3ECE3, dark: 0x1C1A16)
    static let ink = Color(light: 0x2B2622, dark: 0xF2ECE4)
    static let inkSecondary = Color(light: 0x7A7068, dark: 0xA79D93)
    static let hairline = Color(light: 0xE8DFD4, dark: 0x3A352E)
    static let accent = Color(hex: 0xE87A61)
    /// Events not tagged to anyone ("Everyone").
    static let family = Color(light: 0x9C8F84, dark: 0xB3A79B)
}

extension MemberColor {
    /// Strong color: avatar rings, dots, event stripe.
    var strong: Color { Color(hex: googleHex) }
    /// Soft pastel fill for event cards (Skylight look).
    var soft: Color { strong.opacity(0.18) }
}

extension Color {
    /// Dynamic light/dark color from hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
