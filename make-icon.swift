// Zeichnet das App-Icon (1024×1024) und speichert es als icon-1024.png.
// Wird von build-app.sh aufgerufen, wenn AppIcon.icns noch fehlt.
import AppKit

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("Kein Grafikkontext") }

ctx.clear(CGRect(origin: .zero, size: size))

// Abgerundetes Quadrat mit rotem Verlauf (macOS-Stil: mit Rand)
let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
let bgPath = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.32, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.70, green: 0.10, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 512, y: 960),
    end: CGPoint(x: 512, y: 64),
    options: []
)
// Dezenter innerer Lichtrand oben
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
ctx.setLineWidth(6)
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerWidth: 197, cornerHeight: 197, transform: nil))
ctx.strokePath()
ctx.restoreGState()

// Weißes Play-Dreieck mit runden Ecken (Fill + dicker runder Strich)
ctx.setFillColor(NSColor.white.cgColor)
ctx.setStrokeColor(NSColor.white.cgColor)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.setLineWidth(90)
let tri = CGMutablePath()
tri.move(to: CGPoint(x: 405, y: 655))
tri.addLine(to: CGPoint(x: 405, y: 305))
tri.addLine(to: CGPoint(x: 705, y: 480))
tri.closeSubpath()
ctx.addPath(tri)
ctx.drawPath(using: .fillStroke)

// Roter Upload-Pfeil, ins Dreieck "gestanzt"
ctx.setFillColor(NSColor(calibratedRed: 0.82, green: 0.16, blue: 0.14, alpha: 1).cgColor)
let arrow = CGMutablePath()
// Pfeilspitze
arrow.move(to: CGPoint(x: 425, y: 500))
arrow.addLine(to: CGPoint(x: 535, y: 500))
arrow.addLine(to: CGPoint(x: 480, y: 592))
arrow.closeSubpath()
// Schaft
arrow.addRect(CGRect(x: 456, y: 372, width: 48, height: 132))
ctx.addPath(arrow)
ctx.fillPath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG-Erzeugung fehlgeschlagen")
}
let out = URL(fileURLWithPath: "icon-1024.png")
try! png.write(to: out)
print("Icon geschrieben:", out.path)
