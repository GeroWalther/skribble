import AppKit
import Combine
import SwiftUI

/// Owns the screen-annotation mode: the transparent drawing panel that spans
/// every display, the left-edge trigger strips, and the slide-in sidebar.
@MainActor
final class OverlayController: NSObject {
    static let shared = OverlayController()

    private let app = AppState.shared
    private var drawing: Drawing { app.overlayDrawing }
    private var settings: ToolSettings { app.overlaySettings }

    private(set) var overlayPanel: OverlayPanel?
    private var sidebarPanel: SidebarPanel?
    private var edgeTriggers: [EdgeTriggerPanel] = []

    private var sidebarVisible = false
    private var hideWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// The display the sidebar last appeared on — the target for screenshots.
    private var activeScreen: NSScreen?

    private let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))

    var isActive: Bool { overlayPanel != nil }

    private override init() {
        super.init()

        app.$clickThrough
            .sink { [weak self] value in
                self?.overlayPanel?.ignoresMouseEvents = value
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Activation

    func toggle() {
        isActive ? deactivate() : activate()
    }

    func activate() {
        guard !isActive else { return }

        let frame = Self.unionFrame()
        drawing.canvasSize = frame.size

        let panel = OverlayPanel(contentRect: frame, level: overlayLevel)
        // A hair of opacity keeps the transparent panel hit-testable; without it
        // AppKit lets clicks fall straight through to whatever is underneath.
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.003)
        panel.ignoresMouseEvents = app.clickThrough
        panel.contentView = NSHostingView(
            rootView: OverlayRootView(drawing: drawing, settings: settings)
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        overlayPanel = panel

        buildEdgeTriggers()
        app.overlayActive = true

        // Nudge the palette open once so the controls are discoverable.
        showSidebar(on: activeScreenForMouse())
        scheduleHide(after: 2.2)
    }

    func deactivate() {
        guard isActive else { return }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        sidebarPanel?.orderOut(nil)
        sidebarPanel = nil
        sidebarVisible = false

        edgeTriggers.forEach { $0.orderOut(nil) }
        edgeTriggers.removeAll()

        overlayPanel?.orderOut(nil)
        overlayPanel = nil

        app.overlayActive = false
    }

    // MARK: - Geometry

    static func unionFrame() -> NSRect {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Converts a screen's global (y-up) frame into the overlay's local
    /// top-left-origin drawing space.
    private func localRect(for screen: NSScreen) -> CGRect {
        let union = Self.unionFrame()
        return CGRect(x: screen.frame.minX - union.minX,
                      y: union.maxY - screen.frame.maxY,
                      width: screen.frame.width,
                      height: screen.frame.height)
    }

    private func activeScreenForMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    @objc private func screenParametersChanged() {
        guard isActive else { return }
        let frame = Self.unionFrame()
        drawing.canvasSize = frame.size
        overlayPanel?.setFrame(frame, display: true)
        buildEdgeTriggers()
        if sidebarVisible, let screen = activeScreen {
            positionSidebar(on: screen, visible: true, animated: false)
        }
    }

    private func buildEdgeTriggers() {
        edgeTriggers.forEach { $0.orderOut(nil) }
        edgeTriggers = NSScreen.screens.map { screen in
            let trigger = EdgeTriggerPanel(screen: screen,
                                           level: NSWindow.Level(rawValue: overlayLevel.rawValue + 2))
            trigger.onEnter = { [weak self] in
                guard let self, !self.app.isDrawingStroke else { return }
                self.showSidebar(on: screen)
            }
            trigger.orderFrontRegardless()
            return trigger
        }
    }

    // MARK: - Sidebar

    private func makeSidebarPanel(on screen: NSScreen) -> SidebarPanel {
        let height = min(660, screen.frame.height - 60)
        let rect = NSRect(x: screen.frame.minX - SidebarView.width,
                          y: screen.frame.midY - height / 2,
                          width: SidebarView.width,
                          height: height)
        let panel = SidebarPanel(contentRect: rect,
                                 level: NSWindow.Level(rawValue: overlayLevel.rawValue + 1))
        panel.contentView = NSHostingView(rootView: SidebarView(
            settings: settings,
            drawing: drawing,
            onExport: { [weak self] action in self?.export(action) },
            onExit: { [weak self] in self?.deactivate() },
            onHoverChange: { [weak self] hovering in
                guard let self else { return }
                if hovering {
                    self.hideWorkItem?.cancel()
                    self.hideWorkItem = nil
                } else {
                    self.scheduleHide(after: 1.1)
                }
            }
        ))
        return panel
    }

    func showSidebar(on screen: NSScreen) {
        guard isActive else { return }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if sidebarPanel == nil {
            sidebarPanel = makeSidebarPanel(on: screen)
        }
        activeScreen = screen

        guard let panel = sidebarPanel else { return }

        if !sidebarVisible {
            positionSidebar(on: screen, visible: false, animated: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        sidebarVisible = true
        positionSidebar(on: screen, visible: true, animated: true)
    }

    private func hideSidebar() {
        guard sidebarVisible, let panel = sidebarPanel, let screen = activeScreen else { return }
        sidebarVisible = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(sidebarFrame(on: screen, visible: false), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.sidebarVisible else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideSidebar() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func sidebarFrame(on screen: NSScreen, visible: Bool) -> NSRect {
        let height = min(660, screen.frame.height - 60)
        let x = visible ? screen.frame.minX + 12 : screen.frame.minX - SidebarView.width - 4
        return NSRect(x: x,
                      y: screen.frame.midY - height / 2,
                      width: SidebarView.width,
                      height: height)
    }

    private func positionSidebar(on screen: NSScreen, visible: Bool, animated: Bool) {
        guard let panel = sidebarPanel else { return }
        let frame = sidebarFrame(on: screen, visible: visible)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = visible ? 1 : 0
        }
    }

    // MARK: - Keyboard

    /// Command-modified shortcuts, dispatched before the responder chain.
    func handleCommandKey(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":
            mods.contains(.shift) ? drawing.redo() : drawing.undo()
            return true
        case "a":
            drawing.selectAll()
            settings.tool = .select
            return true
        case "c":
            export(.copyAnnotations)
            return true
        default:
            return false
        }
    }

    /// Unmodified keys, reached only when no text field consumed them.
    func handleKey(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.isEmpty || mods == .shift else { return false }

        switch event.keyCode {
        case 53: // esc
            deactivate()
            return true
        case 51, 117: // delete / forward delete
            if drawing.selection.isEmpty { drawing.clear() } else { drawing.deleteSelection() }
            return true
        default:
            break
        }

        guard let tool = Self.toolShortcut(event.charactersIgnoringModifiers?.lowercased()) else {
            return false
        }
        settings.tool = tool
        return true
    }

    static func toolShortcut(_ characters: String?) -> Tool? {
        switch characters {
        case "p": return .pen
        case "h": return .highlighter
        case "l": return .line
        case "a": return .arrow
        case "r": return .rectangle
        case "u": return .roundedRect
        case "o": return .ellipse
        case "g": return .triangle
        case "s": return .star
        case "f": return .bucket
        case "t": return .text
        case "e": return .eraser
        case "v": return .select
        default: return nil
        }
    }

    // MARK: - Export

    func export(_ action: OverlayExportAction) {
        let size = drawing.canvasSize
        switch action {
        case .copyAnnotations:
            Exporter.copyToPasteboard(shapes: drawing.shapes, size: size, background: nil)
        case .saveAnnotationsPNG:
            Exporter.exportWithPanel(format: .png, shapes: drawing.shapes, size: size,
                                     background: nil, suggestedName: "Annotations")
        case .saveAnnotationsPDF:
            Exporter.exportWithPanel(format: .pdf, shapes: drawing.shapes, size: size,
                                     background: nil, suggestedName: "Annotations")
        case .saveScreenshotPNG:
            exportScreenshot(format: .png)
        case .saveScreenshotJPEG:
            exportScreenshot(format: .jpeg)
        case .saveScreenshotPDF:
            exportScreenshot(format: .pdf)
        }
    }

    private func exportScreenshot(format: ExportFormat) {
        guard ScreenCapture.hasPermission() else {
            ScreenCapture.requestPermission()
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission needed"
            alert.informativeText = """
                To save the screen together with your annotations, enable Skribble in \
                System Settings › Privacy & Security › Screen Recording, then relaunch the app.

                You can still export the annotations on their own — they save as a \
                transparent PNG or PDF.
                """
            alert.runModal()
            return
        }

        let screen = activeScreen ?? activeScreenForMouse()
        let rect = localRect(for: screen)
        let offset = CGSize(width: -rect.minX, height: -rect.minY)
        let shapes = drawing.shapes.map { shape -> DrawShape in
            var copy = shape
            copy.translate(by: offset)
            return copy
        }

        Task { @MainActor in
            do {
                let underlay = try await ScreenCapture.capture(screen: screen)
                Exporter.exportWithPanel(format: format,
                                         shapes: shapes,
                                         size: rect.size,
                                         background: nil,
                                         underlay: underlay,
                                         suggestedName: "Screen Annotation")
            } catch {
                Exporter.presentError(error)
            }
        }
    }
}
