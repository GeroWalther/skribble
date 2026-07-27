import AppKit
import SwiftUI

/// One paint document window.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let drawing: Drawing
    let settings: ToolSettings

    private var titleObserver: NSObjectProtocol?

    init(drawing: Drawing) {
        self.drawing = drawing
        self.settings = ToolSettings()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: CanvasWorkspace(drawing: drawing, settings: settings)
        )

        super.init(window: window)
        window.delegate = self
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func updateTitle() {
        window?.title = "Skribble — \(drawing.displayName)"
        window?.isDocumentEdited = drawing.hasUnsavedChanges
    }

    func showCentered() {
        guard let window else { return }
        window.center()
        // Cascade so a second window does not land exactly on the first.
        if let front = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.contentView is NSHostingView<CanvasWorkspace> }) {
            var origin = front.frame.origin
            origin.x += 28
            origin.y -= 28
            window.setFrameOrigin(origin)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard drawing.hasUnsavedChanges, !drawing.shapes.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to “\(drawing.displayName)”?"
        alert.informativeText = "Your drawing will be lost if you don't save it."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return DocumentIO.save(drawing: drawing, saveAs: drawing.fileURL == nil)
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared?.windowClosed(self)
    }
}
