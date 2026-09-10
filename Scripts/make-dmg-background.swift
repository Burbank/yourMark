#!/usr/bin/env swift
import AppKit

// Pixel size must match create-dmg --window-size.
let width: CGFloat = 800
let height: CGFloat = 480
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let paper = NSColor(calibratedRed: 0.965, green: 0.953, blue: 0.933, alpha: 1)
let navy = NSColor(calibratedRed: 0.039, green: 0.145, blue: 0.251, alpha: 1)
let cyan = NSColor(calibratedRed: 0.0, green: 0.631, blue: 0.894, alpha: 1)

paper.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

let headerH: CGFloat = 58
navy.setFill()
NSBezierPath(rect: NSRect(x: 0, y: height - headerH, width: width, height: headerH)).fill()
cyan.setFill()
NSBezierPath(rect: NSRect(x: 0, y: height - headerH - 3, width: width, height: 3)).fill()

func draw(_ text: String, font: NSFont, color: NSColor, at point: NSPoint) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    (text as NSString).draw(at: point, withAttributes: attrs)
}

draw(
    "yourMark",
    font: NSFont.systemFont(ofSize: 28, weight: .bold),
    color: .white,
    at: NSPoint(x: 24, y: height - 44)
)
draw(
    "Drag the app onto Applications",
    font: NSFont.systemFont(ofSize: 16, weight: .medium),
    color: NSColor.white.withAlphaComponent(0.9),
    at: NSPoint(x: 172, y: height - 38)
)

// Finder icon centres: (190, 250) and (610, 250). Arrow sits between them.
// AppKit Y is from the bottom: 480 - 250 = 230.
let midY: CGFloat = 230
navy.setFill()
let shaft = NSBezierPath(roundedRect: NSRect(x: 318, y: midY - 14, width: 108, height: 28), xRadius: 6, yRadius: 6)
shaft.fill()
let head = NSBezierPath()
head.move(to: NSPoint(x: 414, y: midY + 36))
head.line(to: NSPoint(x: 478, y: midY))
head.line(to: NSPoint(x: 414, y: midY - 36))
head.close()
head.fill()

image.unlockFocus()

let dest = URL(fileURLWithPath: CommandLine.arguments[1])
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("failed to write background\n", stderr)
    exit(1)
}
try png.write(to: dest)
print("wrote \(dest.path) \(Int(width))x\(Int(height))")
