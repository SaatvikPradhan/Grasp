import SwiftUI

/// The canvas is a dark stage, so it has one palette rather than light and dark variants.
enum Theme {
    static let paper = Color(hex: 0x0D1615)
    static let surface = Color(hex: 0x14201E)
    static let ink = Color(hex: 0xE5EEEA)
    static let muted = Color(hex: 0x93A5A0)
    static let line = Color(hex: 0x26342F)
    static let grid = Color(hex: 0xE5EEEA).opacity(0.035)
    /// Green: a hand is over something it can grab; money saved.
    static let accent = Color(hex: 0x38C2A8)
    /// Orange: a hand is holding something.
    static let hot = Color(hex: 0xF4B23A)
    /// Red: interest and money lost.
    static let warn = Color(hex: 0xF27A5E)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
