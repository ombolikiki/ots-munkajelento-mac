import SwiftUI
import AppKit

/// Kategóriák színei: alapértelmezés csoportonként, a Beállításokban kategóriánként felülírható.
/// A felülírások `#RRGGBB` szövegként tárolódnak (UserDefaults "categoryColors").
enum CategoryColors {
    /// A felhasználó által módosított színek (az AppModel tartja szinkronban).
    static var overrides: [String: String] = [:]

    static func defaultColor(code: String) -> Color {
        let t = ActivityType.lookup(code: code)
        switch t?.group {
        case "Gyülekezet": return Color(red: 0.20, green: 0.45, blue: 0.80)
        case "Misszió": return Color(red: 0.18, green: 0.62, blue: 0.42)
        case "Továbbképzés": return Color(red: 0.55, green: 0.38, blue: 0.78)
        case "Hivatal": return Color(red: 0.88, green: 0.52, blue: 0.20)
        case "Nem munkaidő": return Color(red: 0.80, green: 0.35, blue: 0.50)
        case ActivityType.customGroup: return Color(red: 0.15, green: 0.58, blue: 0.62)
        default: return Color(red: 0.45, green: 0.50, blue: 0.56)   // Egyéb (Utazás) és ismeretlen
        }
    }

    static func color(code: String) -> Color {
        if let hex = overrides[code], let c = color(hex: hex) { return c }
        return defaultColor(code: code)
    }

    static func isCustomized(_ code: String) -> Bool { overrides[code] != nil }

    static func color(hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func hex(of color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func b(_ x: CGFloat) -> Int { min(255, max(0, Int((x * 255).rounded()))) }
        return String(format: "#%02X%02X%02X", b(c.redComponent), b(c.greenComponent), b(c.blueComponent))
    }
}
