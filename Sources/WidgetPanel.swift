import AppKit
import SwiftUI

/// Borderless panel that drops down from the menu bar icon. Unlike NSPopover it isn't glued to the status item,
/// so it stays put when an auto-hiding menu bar slides away, and as a non-activating panel it takes keyboard
/// focus without pulling the app (or you, out of a full-screen space) to the front.
final class WidgetPanel: NSPanel {
    private let host: NSHostingController<AnyView>
    private var sizeObservation: NSKeyValueObservation?

    /// Called when the SwiftUI content changes size (servers come and go).
    var onResize: (() -> Void)?

    init<Content: View>(rootView: Content, cornerRadius: CGFloat = 12) {
        host = NSHostingController(rootView: AnyView(
            rootView.overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        ))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: cornerRadius)
        contentView = effect

        host.sizingOptions = .preferredContentSize
        host.view.frame = effect.bounds
        host.view.autoresizingMask = [.width, .height]
        effect.addSubview(host.view)
        sizeObservation = host.observe(\.preferredContentSize) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onResize?() }
        }
    }

    var fittingContentSize: NSSize {
        let size = host.preferredContentSize
        return size.width > 0 && size.height > 0 ? size : host.view.fittingSize
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
