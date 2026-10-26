import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scale: scale)
    (transform as NSAffineTransform).concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                            xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.76, blue: 0.72, alpha: 1),
               ending: NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.88, alpha: 1))!
        .draw(in: tile, angle: -55)
    let mouse = NSBezierPath(roundedRect: NSRect(x: 330, y: 220, width: 364, height: 584),
                             xRadius: 182, yRadius: 182)
    NSColor.white.withAlphaComponent(0.97).setFill()
    mouse.fill()
    let wheel = NSBezierPath(roundedRect: NSRect(x: 486, y: 594, width: 52, height: 124),
                             xRadius: 26, yRadius: 26)
    NSColor(calibratedRed: 0.1, green: 0.49, blue: 0.75, alpha: 1).setFill()
    wheel.fill()
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 430, y: 411))
    wave.curve(to: NSPoint(x: 594, y: 411), controlPoint1: NSPoint(x: 475, y: 479),
               controlPoint2: NSPoint(x: 549, y: 343))
    wave.lineWidth = 22
    wave.lineCapStyle = .round
    NSColor(calibratedRed: 0.1, green: 0.49, blue: 0.75, alpha: 1).setStroke()
    wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [Int: [String]] = [
        16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"], 1024: ["icon_512x512@2x.png"]
    ]
    for name in names[size]! { try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name)) }
}
