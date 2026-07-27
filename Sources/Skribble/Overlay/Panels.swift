import AppKit

/// Base for every overlay window: borderless, transparent, above normal windows,
/// present on all Spaces, and non-activating so the app underneath keeps focus.
class FloatingPanel: NSPanel {
    init(contentRect: NSRect, level: NSWindow.Level) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The drawing surface. Handles its own key events because the app is usually
/// not frontmost while annotating, so the main menu's shortcuts never fire.
final class OverlayPanel: FloatingPanel {
    override func keyDown(with event: NSEvent) {
        guard !OverlayController.shared.handleKey(event) else { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only ⌘-shortcuts are intercepted here; plain keys must stay available
        // to a focused text field.
        if OverlayController.shared.handleCommandKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Hosts the slide-in tool palette.
final class SidebarPanel: FloatingPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if OverlayController.shared.handleCommandKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// A sliver pinned to the left edge of a screen. Entering it reveals the sidebar.
/// Kept separate from the overlay so the trigger still works in click-through
/// mode, when the overlay itself ignores the mouse.
final class EdgeTriggerPanel: FloatingPanel {
    var onEnter: (() -> Void)?

    static let thickness: CGFloat = 6

    init(screen: NSScreen, level: NSWindow.Level) {
        let frame = NSRect(x: screen.frame.minX,
                           y: screen.frame.minY,
                           width: Self.thickness,
                           height: screen.frame.height)
        super.init(contentRect: frame, level: level)
        // AppKit lets clicks fall through fully transparent windows, so the strip
        // carries a whisper of color to stay hit-testable.
        backgroundColor = NSColor.white.withAlphaComponent(0.02)
        let view = EdgeTriggerView()
        view.onEnter = { [weak self] in self?.onEnter?() }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
}

private final class EdgeTriggerView: NSView {
    var onEnter: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // A faint vertical hairline plus a brighter grip in the middle, so the
        // trigger is discoverable without being distracting.
        NSColor.white.withAlphaComponent(0.06).setFill()
        bounds.fill()

        let gripHeight: CGFloat = 90
        let grip = NSRect(x: 1,
                          y: bounds.midY - gripHeight / 2,
                          width: bounds.width - 2,
                          height: gripHeight)
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: grip, xRadius: 2, yRadius: 2).fill()
    }
}
