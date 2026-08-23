import SwiftUI

/// Same hex palette as the tkinter build's BG/SURFACE/CARD/... constants in main.py.
enum Palette {
    static let bg = Color(hex: 0x141422)
    static let surface = Color(hex: 0x1e1e2e)
    static let card = Color(hex: 0x252538)
    static let accent = Color(hex: 0x3b82f6)
    static let green = Color(hex: 0x22c55e)
    static let red = Color(hex: 0xef4444)
    static let text = Color(hex: 0xf8fafc)
    static let dim = Color(hex: 0x64748b)
    static let border = Color(hex: 0x2e2e48)
    static let yellow = Color(hex: 0xf59e0b)

    static let slotColors: [Color] = [
        Color(hex: 0x3b82f6), Color(hex: 0x8b5cf6), Color(hex: 0x06b6d4),
        Color(hex: 0xf59e0b), Color(hex: 0x10b981), Color(hex: 0xf43f5e),
    ]
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

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
