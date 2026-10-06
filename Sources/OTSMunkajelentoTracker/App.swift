import SwiftUI
import AppKit

@main
struct OTSMunkajelentoTrackerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
        } label: {
            MenuLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuImages {
    /// Az Adventista jelkép sablonképe (a rendszer fehérre/feketére színezi a menüsor szerint).
    static let adventist: NSImage = {
        guard let data = Data(base64Encoded: LogoData.adventistPNGBase64),
              let img = NSImage(data: data) else { return NSImage() }
        let h: CGFloat = 17
        img.size = NSSize(width: h * CGFloat(LogoData.pixelWidth) / CGFloat(LogoData.pixelHeight), height: h)
        img.isTemplate = true
        return img
    }()
}

/// A menüsori számláló: állandó szélességű, így másodpercenként sem ugrál, és nem tolja az ikont.
/// A menüsori elem nem mindig veszi át a SwiftUI `monospacedDigit()` módosítóját, ezért a betűtípus eleve szélességazonos számjegyű
/// (`monospacedDigitSystemFont`), a keret pedig a szöveg számjegyeinek mért szélességére rögzített (az óó:pp:mm alak csak egy óra után lesz szélesebb).
struct MenuClockText: View {
    let text: String
    static let nsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    /// A szöveg szélessége úgy mérve, hogy minden számjegy 0 (a számjegyek szélessége egyforma, így az érték nem számít).
    static func width(for text: String) -> CGFloat {
        let pattern = String(text.map { $0.isNumber ? Character("0") : $0 })
        return ceil((pattern as NSString).size(withAttributes: [.font: nsFont]).width) + 1
    }

    var body: some View {
        Text(text)
            .font(Font(Self.nsFont as CTFont))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .frame(width: Self.width(for: text), alignment: .leading)
    }
}

struct MenuLabel: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("menuIcon") private var mainIcon = "adventist"
    @AppStorage("menuIcon.pomo") private var pomoIcon = "tomato"
    @AppStorage("menuIcon.break") private var breakIcon = "cup"
    @AppStorage("menuIcon.reminder") private var reminderIcon = "warning"
    @AppStorage("menu.showPomoTime") private var showPomoTime = true

    var body: some View {
        HStack(spacing: 4) {
            IconView(choice: choice)
            if let text = text {
                MenuClockText(text: text)
            }
        }
    }

    /// Pomo közben a pomo-ikon, szünetben a szünet-ikon, egyébként az alap ikon.
    private var choice: IconChoice {
        switch m.pomoPhase {
        case .work: return IconSets.choice(pomoIcon, in: IconSets.pomoWork)
        case .shortBreak, .longBreak: return IconSets.choice(breakIcon, in: IconSets.pomoBreak)
        case .idle:
            // Hosszú kihagyás után az emlékeztető ikon marad, amíg nem lesz új bejegyzés (a futó időzítő ikonja az elsődleges).
            if !m.stopwatchRunning, m.reminderActive { return IconSets.choice(reminderIcon, in: IconSets.reminder) }
            return IconSets.choice(mainIcon, in: IconSets.main)
        }
    }

    private var text: String? {
        if m.stopwatchRunning { return Fmt.clock(m.stopwatchElapsed) }
        if m.pomodoroActive && showPomoTime { return Fmt.clock(m.pomoRemaining) }
        return nil
    }
}
