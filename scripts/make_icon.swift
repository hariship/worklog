// Draws the app icon: a teal rounded square with a notebook page, log lines and a small clock.
// Usage: swift scripts/make_icon.swift <out.png>   (1024x1024)
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Background: macOS icon grid leaves ~10% margin around an 824pt rounded square.
let inset: CGFloat = 100
let bg = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bgPath = NSBezierPath(roundedRect: bg, xRadius: 185, yRadius: 185)
ctx.saveGState()
bgPath.addClip()
NSGradient(colors: [NSColor(red: 0.12, green: 0.62, blue: 0.62, alpha: 1),
                    NSColor(red: 0.05, green: 0.36, blue: 0.45, alpha: 1)])!.draw(in: bg, angle: -90)
ctx.restoreGState()

// Page.
let page = NSRect(x: 262, y: 230, width: 500, height: 590)
NSColor(white: 1, alpha: 0.96).setFill()
NSBezierPath(roundedRect: page, xRadius: 44, yRadius: 44).fill()

// Log lines: a time stub then text, like "- 09:12 standup".
let rows: [(CGFloat, CGFloat)] = [(700, 300), (610, 250), (520, 320), (430, 200)]
for (y, width) in rows {
    NSColor(red: 0.12, green: 0.62, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 322, y: y, width: 70, height: 34), xRadius: 17, yRadius: 17).fill()
    NSColor(white: 0.72, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 412, y: y, width: width, height: 34), xRadius: 17, yRadius: 17).fill()
}

// Clock badge, bottom right.
let clock = NSRect(x: 600, y: 170, width: 250, height: 250)
NSColor(red: 0.98, green: 0.72, blue: 0.20, alpha: 1).setFill()
NSBezierPath(ovalIn: clock).fill()
NSColor.white.setStroke()
let hands = NSBezierPath()
hands.lineWidth = 26
hands.lineCapStyle = .round
hands.move(to: NSPoint(x: clock.midX, y: clock.midY + 70))
hands.line(to: NSPoint(x: clock.midX, y: clock.midY))
hands.line(to: NSPoint(x: clock.midX + 55, y: clock.midY - 30))
hands.stroke()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
