import AppKit
let directory = CommandLine.arguments[1]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)
        let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.18); shadow.shadowBlurRadius = s * 0.04; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.015); shadow.set()
        NSColor(srgbRed: 0.267, green: 0.451, blue: 0.365, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.09, y: s * 0.09, width: s * 0.82, height: s * 0.82), xRadius: s * 0.19, yRadius: s * 0.19).fill()
        NSShadow().set()
        NSColor(srgbRed: 0.96, green: 0.9, blue: 0.64, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.255, y: s * 0.23, width: s * 0.49, height: s * 0.55), xRadius: s * 0.045, yRadius: s * 0.045).fill()
        NSColor(srgbRed: 0.4, green: 0.46, blue: 0.3, alpha: 0.4).setStroke()
        for fraction in [0.46, 0.56, 0.66] {
            let line = NSBezierPath(); line.lineWidth = s * 0.025; line.lineCapStyle = .round
            line.move(to: NSPoint(x: s * 0.35, y: s * fraction)); line.line(to: NSPoint(x: s * 0.65, y: s * fraction)); line.stroke()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
