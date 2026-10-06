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

/// A menüsori számláló képként kirajzolva. A menüsori elem a SwiftUI szövegét a saját betűtípusával (arányos számjegyekkel) rajzolja újra,
/// ezért a számok másodpercenként ugráltak. Itt a szöveget mi rajzoljuk ki egy sablonképre (a rendszer a menüsor színére festi),
/// szélességazonos számjegyű betűtípussal és rögzített szélességgel: minden számjegy ugyanazon a helyen áll, és a kép mérete sosem változik
/// az azonos hosszú időnél (az óó:pp:mm alak egy óra után lesz egyszer szélesebb).
enum MenuClockImage {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let height: CGFloat = 17

    /// A szöveg szélessége úgy mérve, hogy minden számjegy 0 (a számjegyek szélessége egyforma, így az érték nem számít).
    static func width(for text: String) -> CGFloat {
        let pattern = String(text.map { $0.isNumber ? Character("0") : $0 })
        return ceil((pattern as NSString).size(withAttributes: [.font: font]).width) + 1
    }

    static func make(_ text: String) -> NSImage {
        let size = NSSize(width: width(for: text), height: height)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let image = NSImage(size: size, flipped: false) { rect in
            let str = text as NSString
            let h = str.size(withAttributes: attrs).height
            str.draw(at: NSPoint(x: 0, y: (rect.height - h) / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuClockText: View {
    let text: String
    var body: some View {
        Image(nsImage: MenuClockImage.make(text))
            .accessibilityLabel(text)
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
