import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var windowControllers: [MainWindowController] = []
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        MainMenuBuilder.install()
        setUpStatusItem()
        registerHotKeys()
        observeOverlayState()
        newWindow()
        SelfTest.runIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The menu-bar item keeps screen drawing reachable with no windows open.
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { DocumentIO.openDocument(at: url) }
    }

    // MARK: - Windows

    @discardableResult
    func newWindow(with drawing: Drawing? = nil) -> MainWindowController {
        let controller = MainWindowController(drawing: drawing ?? Drawing())
        windowControllers.append(controller)
        controller.showCentered()
        observeTitle(of: controller)
        return controller
    }

    func windowClosed(_ controller: MainWindowController) {
        windowControllers.removeAll { $0 === controller }
    }

    func refreshTitles() {
        windowControllers.forEach { $0.updateTitle() }
    }

    private func observeTitle(of controller: MainWindowController) {
        controller.drawing.$hasUnsavedChanges
            .receive(on: RunLoop.main)
            .sink { [weak controller] _ in controller?.updateTitle() }
            .store(in: &cancellables)
    }

    /// The window a menu command should apply to.
    var frontController: MainWindowController? {
        if let key = NSApp.keyWindow,
           let match = windowControllers.first(where: { $0.window === key }) {
            return match
        }
        return windowControllers.last
    }

    /// Commands follow the window you are actually working in. The overlay only
    /// wins when it (or its sidebar) holds focus, or when no canvas window does —
    /// otherwise exporting from a canvas while screen drawing happened to be on
    /// would silently save the empty annotation layer instead of your artwork.
    private var overlayIsFocused: Bool {
        guard OverlayController.shared.isActive else { return false }
        guard let key = NSApp.keyWindow else { return true }
        return key is FloatingPanel
    }

    private var targetDrawing: Drawing? {
        if overlayIsFocused { return AppState.shared.overlayDrawing }
        return frontController?.drawing
    }

    private var targetSettings: ToolSettings? {
        if overlayIsFocused { return AppState.shared.overlaySettings }
        return frontController?.settings
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "scribble.variable",
                                     accessibilityDescription: "Skribble")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Draw on Screen  ⌃⌥⌘D",
                     action: #selector(toggleOverlay(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Erase Annotations  ⌃⌥⌘E",
                     action: #selector(clearAnnotations(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Toggle Click-Through  ⌃⌥⌘P",
                     action: #selector(toggleClickThrough(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "New Canvas", action: #selector(newCanvas(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Skribble", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func observeOverlayState() {
        AppState.shared.$overlayActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.statusItem?.button?.image = NSImage(
                    systemSymbolName: active ? "scribble.variable.circle.fill" : "scribble.variable",
                    accessibilityDescription: "Skribble"
                )
                self?.statusItem?.button?.image?.isTemplate = true
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        HotKeyManager.shared.register(id: HotKey.toggleOverlay,
                                      keyCode: kVK_ANSI_D,
                                      modifiers: HotKey.modifiers) {
            Task { @MainActor in OverlayController.shared.toggle() }
        }
        HotKeyManager.shared.register(id: HotKey.clearAnnotations,
                                      keyCode: kVK_ANSI_E,
                                      modifiers: HotKey.modifiers) {
            Task { @MainActor in AppState.shared.overlayDrawing.clear() }
        }
        HotKeyManager.shared.register(id: HotKey.clickThrough,
                                      keyCode: kVK_ANSI_P,
                                      modifiers: HotKey.modifiers) {
            Task { @MainActor in AppState.shared.clickThrough.toggle() }
        }
    }

    // MARK: - Menu actions

    @objc func newCanvas(_ sender: Any?) {
        newWindow()
    }

    @objc func openDocument(_ sender: Any?) {
        DocumentIO.open()
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let drawing = frontController?.drawing else { return }
        DocumentIO.save(drawing: drawing, saveAs: false)
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let drawing = frontController?.drawing else { return }
        DocumentIO.save(drawing: drawing, saveAs: true)
    }

    @objc func exportPNG(_ sender: Any?) { export(.png) }
    @objc func exportJPEG(_ sender: Any?) { export(.jpeg) }
    @objc func exportPDF(_ sender: Any?) { export(.pdf) }

    private func export(_ format: ExportFormat) {
        if overlayIsFocused {
            switch format {
            case .png: OverlayController.shared.export(.saveAnnotationsPNG)
            case .pdf: OverlayController.shared.export(.saveAnnotationsPDF)
            case .jpeg: OverlayController.shared.export(.saveScreenshotJPEG)
            }
            return
        }
        guard let drawing = frontController?.drawing else { return }
        Exporter.exportWithPanel(format: format,
                                 shapes: drawing.shapes,
                                 size: drawing.canvasSize,
                                 background: drawing.background,
                                 suggestedName: drawing.displayName)
    }

    @objc func copyDrawing(_ sender: Any?) {
        guard let drawing = targetDrawing else { return }
        Exporter.copyToPasteboard(shapes: drawing.shapes,
                                  size: drawing.canvasSize,
                                  background: drawing.background)
    }

    @objc func undoAction(_ sender: Any?) { targetDrawing?.undo() }
    @objc func redoAction(_ sender: Any?) { targetDrawing?.redo() }
    @objc func deleteSelection(_ sender: Any?) { targetDrawing?.deleteSelection() }
    @objc func selectAllShapes(_ sender: Any?) {
        targetDrawing?.selectAll()
        targetSettings?.tool = .select
    }
    @objc func clearCanvas(_ sender: Any?) { targetDrawing?.clear() }
    @objc func bringToFront(_ sender: Any?) { targetDrawing?.bringSelectionToFront() }
    @objc func sendToBack(_ sender: Any?) { targetDrawing?.sendSelectionToBack() }

    @objc func chooseTool(_ sender: NSMenuItem) {
        guard let tool = Tool(rawValue: sender.representedObject as? String ?? "") else { return }
        targetSettings?.tool = tool
    }

    @objc func toggleOverlay(_ sender: Any?) {
        OverlayController.shared.toggle()
    }

    @objc func clearAnnotations(_ sender: Any?) {
        AppState.shared.overlayDrawing.clear()
    }

    @objc func toggleClickThrough(_ sender: Any?) {
        AppState.shared.clickThrough.toggle()
    }

    @objc func captureScreenWithAnnotations(_ sender: Any?) {
        guard OverlayController.shared.isActive else { return }
        OverlayController.shared.export(.saveScreenshotPNG)
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoAction(_:)):
            return targetDrawing?.canUndo ?? false
        case #selector(redoAction(_:)):
            return targetDrawing?.canRedo ?? false
        case #selector(deleteSelection(_:)), #selector(bringToFront(_:)), #selector(sendToBack(_:)):
            return !(targetDrawing?.selection.isEmpty ?? true)
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)):
            return frontController != nil
        case #selector(toggleOverlay(_:)):
            menuItem.title = OverlayController.shared.isActive
                ? "Stop Drawing on Screen" : "Draw on Screen"
            return true
        case #selector(toggleClickThrough(_:)):
            menuItem.state = AppState.shared.clickThrough ? .on : .off
            return OverlayController.shared.isActive
        case #selector(clearAnnotations(_:)), #selector(captureScreenWithAnnotations(_:)):
            return OverlayController.shared.isActive
        case #selector(chooseTool(_:)):
            let raw = menuItem.representedObject as? String
            menuItem.state = (targetSettings?.tool.rawValue == raw) ? .on : .off
            return true
        default:
            return true
        }
    }
}
