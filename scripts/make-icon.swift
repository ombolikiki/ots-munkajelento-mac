import AppKit

// Használat: swift scripts/make-icon.swift <kimeneti .iconset mappa>
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()
    let rect = NSRect(origin: .zero, size: size).insetBy(dx: CGFloat(px) * 0.06, dy: CGFloat(px) * 0.06)
    let path = NSBezierPath(roundedRect: rect, xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.36, blue: 0.62, alpha: 1),
                        NSColor(red: 0.20, green: 0.55, blue: 0.80, alpha: 1)])?.draw(in: path, angle: -90)
    if let sym = NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: CGFloat(px) * 0.5, weight: .regular)) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        sym.draw(in: NSRect(origin: .zero, size: sym.size))
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let s = tinted.size
        tinted.draw(at: NSPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in sizes {
    if let d = render(px) { try? d.write(to: URL(fileURLWithPath: "\(out)/\(name).png")) }
}
