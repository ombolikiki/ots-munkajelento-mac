import AppKit

/// Fejlesztői ellenőrzés: ha az `OTS_DUMP_STATUS_ITEM` környezeti változó meg van adva (egy fájlútvonal előtagja), az indulás után
/// néhány másodperccel a menüsori elem tartalmát képpé rajzolja (`<előtag>-N.png`), a részleteit szövegfájlba írja (`<előtag>.txt`),
/// majd kilép. Így látható, mit jelenít meg a rendszer a menüsori elemben (kattintás és kisegítő hozzáférés nélkül).
enum StatusItemDump {
    static func scheduleIfRequested() {
        guard let prefix = ProcessInfo.processInfo.environment["OTS_DUMP_STATUS_ITEM"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["OTS_DUMP_DELAY"] ?? "") ?? 13
        // mintavétel: a menüsori elem szélessége és címe másodpercenként (a számláló ugrálásának méréséhez)
        var samples: [String] = []
        for i in 0..<40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i) * 0.25) {
                for w in NSApp.windows where StatusMenuController.isStatusItemWindow(w) {
                    if let cv = w.contentView, let b = buttons(in: cv).first {
                        let f = (b.attributedTitle.length > 0 ? b.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil)?.fontName ?? "-"
                        samples.append("\(b.title)|\(w.frame.width)|\(b.frame.width)|\(f)")
                    }
                }
            }
        }
        sampleStore = { samples }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { dump(prefix) }
    }

    nonisolated(unsafe) private static var sampleStore: () -> [String] = { [] }

    private static func buttons(in view: NSView) -> [NSStatusBarButton] {
        var out: [NSStatusBarButton] = []
        if let b = view as? NSStatusBarButton { out.append(b) }
        for s in view.subviews { out += buttons(in: s) }
        return out
    }

    private static func dump(_ prefix: String) {
        var log = "ablakok: \(NSApp.windows.count) timer.start=\(UserDefaults.standard.double(forKey: "timer.start"))\n"
        var n = 0
        for w in NSApp.windows where StatusMenuController.isStatusItemWindow(w) {
            guard let cv = w.contentView else { continue }
            for b in buttons(in: cv) {
                n += 1
                log += "gomb \(n): cím=„\(b.title)” kép=\(String(describing: b.image?.size)) sablon=\(String(describing: b.image?.isTemplate)) keret=\(b.frame) ablak=\(w.frame) alattaNézetek=\(b.subviews.count)\n"
                // a menüsori elem képe (sablonkép: fekete jelalak fehér háttéren, 4x nagyításban)
                if let img = b.image {
                    let scale: CGFloat = 4
                    let wpx = Int((img.size.width + 4) * scale), hpx = Int((img.size.height + 4) * scale)
                    if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wpx, pixelsHigh: hpx, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                       let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
                        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: wpx, height: hpx).fill()
                        img.draw(in: NSRect(x: 2 * scale, y: 2 * scale, width: img.size.width * scale, height: img.size.height * scale))
                        NSGraphicsContext.restoreGraphicsState()
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-\(n).png"))
                    }
                }
                log += "  attributedTitle=\(b.attributedTitle.string.debugDescription)\n"
                let attrs = b.attributedTitle.length > 0 ? b.attributedTitle.attributes(at: 0, effectiveRange: nil) : [:]
                log += "  attrs=\(attrs)\n  button.font=\(String(describing: b.font)) cell.font=\(String(describing: b.cell?.font))\n"
                // a gomb saját kirajzolása (ha a rendszer engedi)
                if let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) {
                    b.cacheDisplay(in: b.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(prefix)-gomb-\(n).png"))
                }
            }
        }
        if n == 0 { log += "nincs menüsori gomb\n" }
        let ss = sampleStore()
        log += "minták (cím|ablak szélesség|gomb szélesség|betűtípus): \(ss.count)\n" + ss.joined(separator: "\n") + "\n"
        log += "különböző ablakszélességek: \(Set(ss.map { $0.split(separator: "|").dropFirst().first.map(String.init) ?? "" }).sorted())\n"
        try? log.write(toFile: prefix + ".txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
