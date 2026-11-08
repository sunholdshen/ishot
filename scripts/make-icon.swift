import AppKit
let destination = CommandLine.arguments[1]
try! FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: pixels, height: pixels)
        let gc = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
        let ctx = gc.cgContext; ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205).fill()
        NSColor(calibratedRed: 0.4, green: 0.92, blue: 0.76, alpha: 1).setStroke()
        let corners = NSBezierPath(); corners.lineWidth = 46; corners.lineCapStyle = .round; corners.lineJoinStyle = .round
        for (x, y, sx, sy) in [(280.0, 280.0, 1.0, 1.0), (744.0, 280.0, -1.0, 1.0), (280.0, 744.0, 1.0, -1.0), (744.0, 744.0, -1.0, -1.0)] {
            corners.move(to: NSPoint(x: x, y: y + sy * 100)); corners.line(to: NSPoint(x: x, y: y)); corners.line(to: NSPoint(x: x + sx * 100, y: y))
        }
        corners.stroke()
        NSColor.white.setFill()
        let pin = NSBezierPath(); pin.move(to: NSPoint(x: 450, y: 680)); pin.line(to: NSPoint(x: 650, y: 580)); pin.line(to: NSPoint(x: 598, y: 530)); pin.line(to: NSPoint(x: 590, y: 420)); pin.line(to: NSPoint(x: 498, y: 466)); pin.line(to: NSPoint(x: 380, y: 320)); pin.line(to: NSPoint(x: 450, y: 490)); pin.line(to: NSPoint(x: 360, y: 535)); pin.line(to: NSPoint(x: 448, y: 600)); pin.close(); pin.fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name))
    }
}
