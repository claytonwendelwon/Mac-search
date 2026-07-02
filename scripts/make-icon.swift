// Renders the master icon artwork into a macOS-style app icon:
// a rounded-rect (squircle-ish) tile at Apple's 824/1024 icon-grid size,
// centered on a transparent 1024x1024 canvas.
//
// Usage: swift scripts/make-icon.swift <input.png> <output.png>
import AppKit

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <input.png> <output.png>\n".utf8))
    exit(1)
}
let outputPath = CommandLine.arguments[2]

let canvas: CGFloat = 1024
let tile: CGFloat = 824          // Apple icon grid: artwork tile size
let radius: CGFloat = 185.4      // Apple icon grid: corner radius at 1024pt

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tileRect = NSRect(x: (canvas - tile) / 2, y: (canvas - tile) / 2, width: tile, height: tile)
NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius).addClip()

// Aspect-fill the artwork into the tile (center-crops non-square masters).
let sourceSize = source.size
let scale = max(tileRect.width / sourceSize.width, tileRect.height / sourceSize.height)
let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
let drawRect = NSRect(x: tileRect.midX - drawSize.width / 2,
                      y: tileRect.midY - drawSize.height / 2,
                      width: drawSize.width, height: drawSize.height)
source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outputPath))
