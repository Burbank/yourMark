#!/usr/bin/env swift
import AppKit

let width: CGFloat = 720
let height: CGFloat = 440
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let paper = NSColor(calibratedRed: 0.956, green: 0.937, blue: 0.902, alpha: 1)
let navy = NSColor(calibratedRed: 0.039, green: 0.145, blue: 0.251, alpha: 1)
let cyan = NSColor(calibratedRed: 0.0, green: 0.631, blue: 0.894, alpha: 1)
let line = NSColor(calibratedRed: 0.91, green: 0.88, blue: 0.82, alpha: 1)

paper.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

var y: CGFloat = 0
while y < height {
    line.setStroke()
    let p = NSBezierPath()
    p.lineWidth = 1
    p.move(to: NSPoint(x: 0, y: y))
    p.line(to: NSPoint(x: width, y: y))
    p.stroke()
    y += 8
}

let headerH: CGFloat = 56
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
    at: NSPoint(x: 22, y: height - 44)
)
draw(
    "Drag yourMark onto Applications",
    font: NSFont.systemFont(ofSize: 15, weight: .medium),
    color: NSColor.white.withAlphaComponent(0.88),
    at: NSPoint(x: 168, y: height - 38)
)

// Arrow sits between the two large icons (centers ~180 and 540, y ~210).
let midY: CGFloat = 218
let shaft = NSBezierPath(roundedRect: NSRect(x: 292, y: midY - 10, width: 96, height: 20), xRadius: 4, yRadius: 4)
navy.setFill()
shaft.fill()
let head = NSBezierPath()
head.move(to: NSPoint(x: 380, y: midY + 28))
head.line(to: NSPoint(x: 428, y: midY))
head.line(to: NSPoint(x: 380, y: midY - 28))
head.close()
head.fill()

image.unlockFocus()

let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("failed to write background\n", stderr)
    exit(1)
}
try png.write(to: root)
print("wrote \(root.path)")
