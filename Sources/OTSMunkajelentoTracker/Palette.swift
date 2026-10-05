import SwiftUI

/// Színséma: a kiemelő szín és az átmenet. A jelentésű színek (zöld/piros/narancs) a `Theme`-ben fixek.
struct Palette: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: Color
    let accent2: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let blue = Palette(id: "blue", name: "Kék",
                              accent: Color(red: 0.16, green: 0.42, blue: 0.74), accent2: Color(red: 0.22, green: 0.60, blue: 0.86))
    static let green = Palette(id: "green", name: "Zöld",
                               accent: Color(red: 0.10, green: 0.46, blue: 0.40), accent2: Color(red: 0.24, green: 0.66, blue: 0.50))
    static let purple = Palette(id: "purple", name: "Lila",
                                accent: Color(red: 0.40, green: 0.26, blue: 0.70), accent2: Color(red: 0.62, green: 0.42, blue: 0.88))
    static let amber = Palette(id: "amber", name: "Borostyán",
                               accent: Color(red: 0.78, green: 0.40, blue: 0.08), accent2: Color(red: 0.95, green: 0.64, blue: 0.20))

    static let all: [Palette] = [blue, green, purple, amber]

    static func byID(_ id: String) -> Palette { all.first { $0.id == id } ?? blue }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.blue }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Megjelenési mód: rendszer / világos / sötét. Az egész alkalmazás összes ablakára érvényes.
enum AppearanceManager {
    static let key = "appearance"

    static func apply() {
        let mode = UserDefaults.standard.string(forKey: key) ?? "system"
        let appearance: NSAppearance?
        switch mode {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil
        }
        if NSApplication.shared.appearance?.name != appearance?.name {
            NSApplication.shared.appearance = appearance
        }
    }
}
