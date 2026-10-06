import SwiftUI
import AppKit

@main
struct OTSMunkajelentoTrackerApp: App {
    @StateObject private var model = AppModel()

    init() { StatusItemDump.scheduleIfRequested() }

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

/// A menüsori számláló: állandó szélességű, nem ugrál.
///
/// A SwiftUI a menüsori címkét **egy képre és egy szövegre** bontja, a szöveget pedig mindig a rendszer saját, arányos számjegyű
/// betűtípusával adja át a menüsori gombnak (a `font` és a `monospacedDigit` módosítót eldobja), a gomb szélességét ebből méri;
/// második kép nem fér a címkébe, és a gomb címét utólag a rendszer visszaállítja. Mért eredmény: az elem szélessége másodpercenként
/// 73 és 76 pont között ugrált. Megoldás: ha idő látszik, a címke **egyetlen kép**, amelyben az ikont és az időt mi rajzoljuk ki
/// szélességazonos számjegyű betűtípussal, így minden számjegy ugyanazon a helyen áll, és a kép mérete sosem változik.
enum MenuBarClock {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    static let height: CGFloat = 17
    static let gap: CGFloat = 4
    static let scale: CGFloat = 3

    /// Az idő szélessége úgy mérve, hogy minden számjegy 0 (a számjegyek szélessége egyforma, így az érték nem számít).
    static func clockWidth(for text: String) -> CGFloat {
        let pattern = String(text.map { $0.isNumber ? Character("0") : $0 })
        return ceil((pattern as NSString).size(withAttributes: [.font: font]).width) + 1
    }

    /// Az ikon a rajzoláshoz: (kép, sablon-e). A szimbólum és az Adventista jelkép sablon (a rendszer a menüsor színére festi),
    /// az emoji színes.
    private static func iconImage(_ icon: IconChoice) -> (NSImage?, template: Bool) {
        switch icon.kind {
        case .symbol(let name):
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            return (NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg), true)
        case .logo:
            return (MenuImages.adventist, true)
        case .emoji:
            return (nil, false)
        }
    }

    /// A menüsor szövegének színe a menüsori gomb megjelenése szerint (csak a színes, nem sablon változathoz kell).
    static func statusTextColor() -> NSColor {
        let appearance = statusButton()?.effectiveAppearance ?? NSApp.effectiveAppearance
        var color = NSColor.black
        appearance.performAsCurrentDrawingAppearance { color = NSColor.controlTextColor.usingColorSpace(.sRGB) ?? .black }
        return color
    }

    static func statusButton() -> NSStatusBarButton? {
        func find(_ v: NSView) -> NSStatusBarButton? {
            if let b = v as? NSStatusBarButton { return b }
            for s in v.subviews { if let b = find(s) { return b } }
            return nil
        }
        for w in NSApp.windows where StatusMenuController.isStatusItemWindow(w) {
            if let cv = w.contentView, let b = find(cv) { return b }
        }
        return nil
    }

    /// Az ikon és az idő egyetlen képen. Sablonkép, ha az ikon szimbólum vagy jelkép (fekete rajz, a rendszer festi); emoji ikonnál színes
    /// kép, az idő `textColor` színű.
    static func make(icon: IconChoice, text: String, textColor: NSColor) -> NSImage {
        let (iconImg, isTemplate) = iconImage(icon)
        let iconText = { () -> String? in if case .emoji(let e) = icon.kind { return e }; return nil }()
        let emojiFont = NSFont.systemFont(ofSize: 14)
        var iconWidth: CGFloat = 0
        if let img = iconImg {
            let h = min(height, img.size.height)
            iconWidth = ceil(img.size.width * h / max(1, img.size.height))
        } else if let e = iconText {
            iconWidth = ceil((e as NSString).size(withAttributes: [.font: emojiFont]).width)
        }
        let clockW = clockWidth(for: text)
        let width = iconWidth + (iconWidth > 0 ? gap : 0) + clockW
        let wpx = Int(ceil(width * scale)), hpx = Int(height * scale)
        let result = NSImage(size: NSSize(width: width, height: height))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wpx, pixelsHigh: hpx, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return result }
        rep.size = result.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)
        let ink: NSColor = isTemplate ? .black : textColor
        if let img = iconImg {
            let h = min(height, img.size.height)
            let rect = NSRect(x: 0, y: (height - h) / 2, width: iconWidth, height: h)
            // a sablonképet feketére festjük (a rendszer a sablonkép alakját veszi, a színét maga adja)
            let tinted = img.copy() as? NSImage ?? img
            tinted.lockFocus()
            NSColor.black.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        } else if let e = iconText {
            let h = (e as NSString).size(withAttributes: [.font: emojiFont]).height
            (e as NSString).draw(at: NSPoint(x: 0, y: (height - h) / 2), withAttributes: [.font: emojiFont])
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let th = (text as NSString).size(withAttributes: attrs).height
        (text as NSString).draw(at: NSPoint(x: iconWidth + (iconWidth > 0 ? gap : 0), y: (height - th) / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        result.addRepresentation(rep)
        result.isTemplate = isTemplate
        return result
    }
}

struct MenuLabel: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("menuIcon") private var mainIcon = "adventist"
    @AppStorage("menuIcon.pomo") private var pomoIcon = "tomato"
    @AppStorage("menuIcon.break") private var breakIcon = "cup"
    @AppStorage("menuIcon.reminder") private var reminderIcon = "warning"

    var body: some View {
        if let text = m.menuClockText {
            // idő látszik: egyetlen kép (ikon és idő együtt, állandó szélességgel)
            let isEmoji: Bool = { if case .emoji = choice.kind { return true }; return false }()
            Image(nsImage: MenuBarClock.make(icon: choice, text: text, textColor: MenuBarClock.statusTextColor()))
                .renderingMode(isEmoji ? .original : .template)
                .accessibilityLabel(text)
        } else {
            IconView(choice: choice)
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
}
