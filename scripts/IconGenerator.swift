import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: IconGenerator.swift OUTPUT.png\n", stderr)
    exit(2)
}

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

let backgroundRect = NSRect(x: 56, y: 56, width: 912, height: 912)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 218, yRadius: 218)
NSGradient(
    colors: [
        NSColor(calibratedRed: 0.08, green: 0.38, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.26, green: 0.14, blue: 0.68, alpha: 1)
    ]
)?.draw(in: background, angle: -55)

let glow = NSBezierPath(ovalIn: NSRect(x: 155, y: 470, width: 710, height: 450))
NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
glow.fill()

if let symbol = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 520, weight: .semibold)) {
    symbol.isTemplate = true
    NSColor.white.set()
    symbol.draw(
        in: NSRect(x: 252, y: 235, width: 520, height: 570),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.96
    )
}

let dot = NSBezierPath(ovalIn: NSRect(x: 716, y: 204, width: 116, height: 116))
NSColor(calibratedRed: 0.22, green: 0.95, blue: 0.58, alpha: 1).setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
