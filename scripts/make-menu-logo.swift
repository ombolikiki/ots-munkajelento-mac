import AppKit

// Használat: swift scripts/make-menu-logo.swift <forrás .png> <kimenet .swift>
// A fekete-fehér Adventista jelképből (® nélkül) alfa-maszkot készít, és base64-ben beágyazza.
let src = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
guard let image = NSImage(contentsOfFile: src),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("nem olvasható") }

let cropped = cg
let cropW = cg.width

let targetH = 64
let targetW = Int((Double(cropW) / Double(cg.height) * Double(targetH)).rounded())
let cs = CGColorSpaceCreateDeviceGray()
guard let gctx = CGContext(data: nil, width: targetW, height: targetH, bitsPerComponent: 8, bytesPerRow: targetW,
                           space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { fatalError() }
gctx.interpolationQuality = .high
gctx.setFillColor(gray: 1, alpha: 1)
gctx.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
gctx.draw(cropped, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
// A ® jel kitakarása (a jobb oldali könyvszárnytól jobbra, felül van): a méretarányok a forrásképre vonatkoznak
gctx.setFillColor(gray: 1, alpha: 1)
let H = CGFloat(targetH), W = CGFloat(targetW)
gctx.fill(CGRect(x: 0.935 * W, y: (1 - 0.915) * H, width: 0.065 * W + 1, height: (0.915 - 0.80) * H))
let gray = gctx.data!.assumingMemoryBound(to: UInt8.self)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: targetW, pixelsHigh: targetH, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<targetH {
    for x in 0..<targetW {
        let a = 255 - Int(gray[y * targetW + x])   // sötét = átlátszatlan
        let p = rep.bitmapData! + y * rep.bytesPerRow + x * 4
        p[0] = 0; p[1] = 0; p[2] = 0; p[3] = UInt8(a)
    }
}
let png = rep.representation(using: .png, properties: [:])!
let swift = """
// Generálva: scripts/make-menu-logo.swift (az Adventista jelkép alfa-maszkja, \(targetW)x\(targetH) px)
enum LogoData {
    static let adventistPNGBase64 = "\(png.base64EncodedString())"
    static let pixelWidth = \(targetW)
    static let pixelHeight = \(targetH)
}
"""
try swift.write(toFile: out, atomically: true, encoding: .utf8)
print("ok \(targetW)x\(targetH), \(png.count) bájt")
