import AppKit

/// Portly's round little face, drawn as a template image so it tints like any other menu bar icon.
/// Filled while servers are running, outlined when idle.
enum PortlyIcon {
    static func image(filled: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current else { return false }
            let transform = NSAffineTransform()
            transform.scale(by: rect.width / 18)
            transform.concat()

            NSColor.black.set()
            let body = bodyPath()
            if filled {
                body.fill()
                ctx.compositingOperation = .destinationOut
                facePath().fill()
            } else {
                body.lineWidth = 1.5
                body.stroke()
                facePath().fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // 18×18 canvas, origin bottom-left.
    private static func bodyPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 1.5, y: 7))
        p.curve(to: NSPoint(x: 9, y: 15), controlPoint1: NSPoint(x: 1.5, y: 12.2), controlPoint2: NSPoint(x: 4.7, y: 15))
        p.curve(to: NSPoint(x: 16.5, y: 7), controlPoint1: NSPoint(x: 13.3, y: 15), controlPoint2: NSPoint(x: 16.5, y: 12.2))
        p.curve(to: NSPoint(x: 13, y: 3), controlPoint1: NSPoint(x: 16.5, y: 4.6), controlPoint2: NSPoint(x: 15.3, y: 3))
        p.line(to: NSPoint(x: 5, y: 3))
        p.curve(to: NSPoint(x: 1.5, y: 7), controlPoint1: NSPoint(x: 2.7, y: 3), controlPoint2: NSPoint(x: 1.5, y: 4.6))
        p.close()
        return p
    }

    private static func facePath() -> NSBezierPath {
        let p = NSBezierPath(ovalIn: NSRect(x: 5.4, y: 8.1, width: 1.9, height: 2.3))
        p.append(NSBezierPath(ovalIn: NSRect(x: 10.7, y: 8.1, width: 1.9, height: 2.3)))
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 7.7, y: 7.2))
        mouth.curve(to: NSPoint(x: 10.3, y: 7.2), controlPoint1: NSPoint(x: 7.9, y: 5.4), controlPoint2: NSPoint(x: 10.1, y: 5.4))
        mouth.close()
        p.append(mouth)
        return p
    }
}
