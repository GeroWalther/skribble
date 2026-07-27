import AppKit
import Combine

/// Global state for the screen-annotation mode, shared by the overlay canvas,
/// the pop-out sidebar, the menu bar item and the main menu.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let overlayDrawing = Drawing(canvasSize: .zero, background: nil)
    let overlaySettings = ToolSettings(
        tool: .pen,
        strokeColor: .red,
        useFill: false,
        lineWidth: 6,
        fontSize: 34
    )

    @Published var overlayActive = false

    /// When on, the overlay stops intercepting the mouse so you can keep using
    /// the apps underneath. The sidebar and edge trigger stay live.
    @Published var clickThrough = false

    /// Optional dimming behind the annotations, for presenting.
    @Published var dimLevel: Double = 0

    /// Suppresses the edge trigger while a stroke is in progress.
    @Published var isDrawingStroke = false

    private init() {}
}
