import SwiftUI
import AppKit

// Peek's brand accent — "nishan crimson" (#d13a63). Used everywhere the UI
// would otherwise fall back to the system accent color.
extension Color {
    static let peekAccent = Color(red: 0xD1 / 255, green: 0x3A / 255, blue: 0x63 / 255)
}

extension NSColor {
    static let peekAccent = NSColor(srgbRed: 0xD1 / 255, green: 0x3A / 255, blue: 0x63 / 255, alpha: 1)
}
