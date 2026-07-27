import AppKit

/// In-process integration check, run with `SKRIBBLE_SELFTEST=1`.
/// Synthesizes a real drag into the live overlay panel and reports whether the
/// stroke reached `Drawing.shapes` and whether an export contains pixels.
@MainActor
enum SelfTest {

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["SKRIBBLE_SELFTEST"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { run() }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write("[selftest] \(message)\n".data(using: .utf8)!)
    }

    private static func run() {
        let controller = OverlayController.shared
        let drawing = AppState.shared.overlayDrawing
        AppState.shared.overlaySettings.tool = .pen

        controller.activate()
        log("overlay active=\(controller.isActive) canvasSize=\(drawing.canvasSize)")

        guard let panel = controller.overlayPanel else {
            log("FAIL: no overlay panel")
            NSApp.terminate(nil)
            return
        }
        log("panel frame=\(panel.frame) key=\(panel.isKeyWindow) ignoresMouse=\(panel.ignoresMouseEvents)")
        log("shapes before drag = \(drawing.shapes.count)")

        // Drag across the middle of the panel, in window (y-up) coordinates.
        let height = panel.frame.height
        let path: [CGPoint] = (0...10).map { CGPoint(x: 300 + CGFloat($0) * 30, y: height / 2) }

        send(.leftMouseDown, at: path[0], to: panel)
        for point in path.dropFirst() {
            send(.leftMouseDragged, at: point, to: panel)
        }
        send(.leftMouseUp, at: path.last!, to: panel)

        // Let SwiftUI flush the gesture before inspecting state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { report(drawing) }
    }

    private static func send(_ type: NSEvent.EventType, at point: CGPoint, to panel: NSPanel) {
        guard let event = NSEvent.mouseEvent(with: type,
                                             location: point,
                                             modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: panel.windowNumber,
                                             context: nil,
                                             eventNumber: 0,
                                             clickCount: 1,
                                             pressure: type == .leftMouseUp ? 0 : 1) else {
            log("could not synthesize \(type.rawValue)")
            return
        }
        panel.sendEvent(event)
    }

    private static func report(_ drawing: Drawing) {
        log("shapes after drag = \(drawing.shapes.count)")
        for shape in drawing.shapes {
            log("  shape tool=\(shape.tool.rawValue) points=\(shape.points.count) "
                + "first=\(shape.points.first.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "-") "
                + "width=\(shape.lineWidth)")
        }

        let outDir = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["SKRIBBLE_SELFTEST_OUT"] ?? NSTemporaryDirectory())

        do {
            let png = try Exporter.pngData(shapes: drawing.shapes,
                                           size: drawing.canvasSize,
                                           background: nil)
            try png.write(to: outDir.appendingPathComponent("selftest.png"))
            let rep = NSBitmapImageRep(data: png)!
            var opaque = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                    if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.1 { opaque += 1 }
                }
            }
            log("export png \(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh), opaque samples=\(opaque)")
        } catch {
            log("export failed: \(error)")
        }

        log(drawing.shapes.isEmpty ? "RESULT: stroke never reached the model"
                                   : "RESULT: stroke committed to the model")
        NSApp.terminate(nil)
    }
}
