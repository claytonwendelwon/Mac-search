import AppKit

/// Small template icon for the macOS menu bar.
///
/// The full app icon is too detailed at 18pt, so the menu-bar mark is a
/// simplified "beacon lens": a search ring/handle with a center dot. Because
/// the image is a template, macOS tints it to match light/dark menu-bar
/// appearances.
enum BeaconMenuIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let center = NSPoint(x: size * 0.48, y: size * 0.53)
        let ringRadius = size * 0.24

        // Search lens ring.
        let ringRect = NSRect(x: center.x - ringRadius,
                              y: center.y - ringRadius,
                              width: ringRadius * 2,
                              height: ringRadius * 2)
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = 1.8
        ring.stroke()

        // Short search handle.
        let handle = NSBezierPath()
        handle.lineWidth = 2.0
        handle.lineCapStyle = .round
        handle.move(to: NSPoint(x: center.x + ringRadius * 0.72,
                                y: center.y - ringRadius * 0.72))
        handle.line(to: NSPoint(x: size * 0.79, y: size * 0.20))
        handle.stroke()

        // Beacon dot.
        let dotRadius = size * 0.095
        NSBezierPath(ovalIn: NSRect(x: center.x - dotRadius,
                                    y: center.y - dotRadius,
                                    width: dotRadius * 2,
                                    height: dotRadius * 2)).fill()

        return image
    }
}
