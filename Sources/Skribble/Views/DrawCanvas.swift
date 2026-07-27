import AppKit
import SwiftUI

/// Resize grips around the current selection.
enum Handle: String, CaseIterable, Identifiable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var id: String { rawValue }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func resized(_ rect: CGRect, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch self {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }
}

/// The drawing surface. Used both for the paint window (opaque page) and for the
/// full-screen annotation overlay (transparent).
struct DrawCanvas: View {
    @ObservedObject var drawing: Drawing
    @ObservedObject var settings: ToolSettings

    /// Overlay mode drops the drop-shadow/page chrome and reports stroke state
    /// so the sidebar's edge trigger can stand down mid-stroke.
    var isOverlay: Bool = false

    private enum DragMode { case none, draw, erase, move, marquee }

    private static let space = "SkribbleCanvas"

    @State private var dragMode: DragMode = .none
    @State private var dragActive = false
    @State private var dragStart: CGPoint = .zero
    @State private var preview: DrawShape?
    @State private var marquee: CGRect?
    @State private var hoverPoint: CGPoint?

    @State private var moveOriginals: [UUID: [CGPoint]] = [:]
    @State private var didSnapshot = false

    @State private var resizeOriginals: [UUID: DrawShape]?
    @State private var resizeStartRect: CGRect = .zero

    @State private var isEditingText = false
    @State private var editingID: UUID?
    @State private var editingText = ""
    @State private var editingOrigin: CGPoint = .zero
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvasLayer
            marqueeLayer
            selectionLayer
            eraserCursorLayer
            textEditorLayer
        }
        .frame(width: drawing.canvasSize.width, height: drawing.canvasSize.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .onChange(of: settings.tool) { commitText() }
    }

    // MARK: - Layers

    private var visibleShapes: [DrawShape] {
        var result = drawing.shapes
        if let editingID {
            result.removeAll { $0.id == editingID }
        }
        if let preview {
            result.append(preview)
        }
        return result
    }

    private var canvasLayer: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                Renderer.render(shapes: visibleShapes,
                                size: size,
                                background: drawing.background,
                                in: cg)
            }
        }
        .frame(width: drawing.canvasSize.width, height: drawing.canvasSize.height)
        // A near-invisible fill guarantees the transparent overlay window still
        // hit-tests, and gives the paint canvas a hit area outside its strokes.
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .gesture(primaryDrag)
        .simultaneousGesture(doubleTap)
        .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
            switch phase {
            case .active(let point): hoverPoint = point
            case .ended: hoverPoint = nil
            }
        }
    }

    @ViewBuilder private var marqueeLayer: some View {
        if let marquee {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var selectionLayer: some View {
        if settings.tool == .select, let bounds = drawing.selectionBounds {
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: bounds.width, height: bounds.height)
                .offset(x: bounds.minX, y: bounds.minY)
                .allowsHitTesting(false)

            ForEach(Handle.allCases) { handle in
                let point = handle.position(in: bounds)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .offset(x: point.x - 5, y: point.y - 5)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                            .onChanged { resizeChanged(handle, to: $0.location, bounds: bounds) }
                            .onEnded { _ in resizeEnded() }
                    )
            }
        }
    }

    @ViewBuilder private var eraserCursorLayer: some View {
        if settings.tool == .eraser, let hoverPoint {
            let diameter = settings.effectiveLineWidth(for: .eraser)
            Circle()
                .strokeBorder(Color.red.opacity(0.85), lineWidth: 1.5)
                .background(Circle().fill(Color.white.opacity(0.15)))
                .frame(width: diameter, height: diameter)
                .offset(x: hoverPoint.x - diameter / 2, y: hoverPoint.y - diameter / 2)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var textEditorLayer: some View {
        if isEditingText {
            TextField("Type…", text: $editingText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: settings.fontSize, weight: .semibold))
                .foregroundStyle(settings.strokeColor.color)
                .focused($textFieldFocused)
                .frame(minWidth: 160, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.accentColor.opacity(0.7),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        )
                )
                .offset(x: editingOrigin.x - 4, y: editingOrigin.y - 4)
                .onSubmit { commitText() }
                .onExitCommand { commitText() }
        }
    }

    // MARK: - Gestures

    private var primaryDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !dragActive {
                    dragActive = true
                    dragStart = value.startLocation
                    beginDrag(at: value.startLocation)
                }
                continueDrag(to: value.location)
            }
            .onEnded { value in
                endDrag(at: value.location)
            }
    }

    private var doubleTap: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .named(Self.space))
            .onEnded { value in
                guard settings.tool == .select || settings.tool == .text else { return }
                if let hit = drawing.shape(at: value.location), hit.tool == .text {
                    startEditing(existing: hit)
                }
            }
    }

    // MARK: - Drag handling

    private func beginDrag(at point: CGPoint) {
        if isEditingText { commitText() }
        if isOverlay { AppState.shared.isDrawingStroke = true }
        didSnapshot = false

        switch settings.tool {
        case .select:
            if let hit = drawing.shape(at: point) {
                if !drawing.selection.contains(hit.id) {
                    if !NSEvent.modifierFlags.contains(.shift) { drawing.selection.removeAll() }
                    drawing.selection.insert(hit.id)
                }
                moveOriginals = Dictionary(uniqueKeysWithValues:
                    drawing.selectedShapes.map { ($0.id, $0.points) })
                dragMode = .move
            } else {
                if !NSEvent.modifierFlags.contains(.shift) { drawing.selection.removeAll() }
                dragMode = .marquee
            }

        case .eraser:
            dragMode = .erase

        case .text, .bucket:
            // Click actions resolve on mouse-up so a stray drag cannot trigger them.
            dragMode = .none

        default:
            dragMode = .draw
            var shape = settings.makeShape(tool: settings.tool, at: point)
            if settings.tool.isDragDefined { shape.points = [point, point] }
            preview = shape
        }
    }

    private func continueDrag(to point: CGPoint) {
        switch dragMode {
        case .draw:
            guard preview != nil else { return }
            if settings.tool.isFreehand {
                preview?.points.append(point)
            } else {
                preview?.points = [dragStart, constrainedPoint(from: dragStart, to: point)]
            }

        case .erase:
            let radius = settings.effectiveLineWidth(for: .eraser) / 2
            guard drawing.shapes.contains(where: { $0.hitTest(point, tolerance: radius) }) else { return }
            if !didSnapshot { drawing.beginChange(); didSnapshot = true }
            drawing.erase(at: point, radius: radius)

        case .move:
            let delta = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            guard abs(delta.width) > 0.01 || abs(delta.height) > 0.01 else { return }
            if !didSnapshot { drawing.beginChange(); didSnapshot = true }
            for index in drawing.shapes.indices {
                guard let original = moveOriginals[drawing.shapes[index].id] else { continue }
                drawing.shapes[index].points = original.map {
                    CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
                }
            }

        case .marquee:
            marquee = CGRect(x: min(dragStart.x, point.x), y: min(dragStart.y, point.y),
                             width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y))

        case .none:
            break
        }
    }

    private func endDrag(at point: CGPoint) {
        switch dragMode {
        case .draw:
            if let shape = preview, isMeaningful(shape) {
                drawing.add(shape)
            }
            preview = nil

        case .marquee:
            if let rect = marquee, rect.width > 2 || rect.height > 2 {
                let ids = drawing.shapes.filter { $0.intersects(rect) }.map(\.id)
                drawing.selection.formUnion(ids)
            }
            marquee = nil

        case .none:
            switch settings.tool {
            case .text:
                // A plain click with the text tool drops a new text box.
                if let hit = drawing.shape(at: point), hit.tool == .text {
                    startEditing(existing: hit)
                } else {
                    startEditing(at: point)
                }
            case .bucket:
                applyBucket(at: point)
            default:
                break
            }

        case .erase, .move:
            break
        }

        dragActive = false
        dragMode = .none
        moveOriginals = [:]
        if isOverlay { AppState.shared.isDrawingStroke = false }
    }

    /// Paint bucket: fills the topmost closed shape under the pointer with the
    /// current color. Option-click clears the fill again. Clicking bare canvas
    /// repaints the page — but never in overlay mode, where that would drop an
    /// opaque sheet over the whole screen.
    private func applyBucket(at point: CGPoint) {
        let clearing = NSEvent.modifierFlags.contains(.option)

        if let hit = drawing.shapes.reversed().first(where: { $0.fillHitTest(point) }),
           let index = drawing.shapes.firstIndex(where: { $0.id == hit.id }) {
            let newFill = clearing ? nil : settings.strokeColor
            guard drawing.shapes[index].fill != newFill else { return }
            drawing.beginChange()
            drawing.shapes[index].fill = newFill
            return
        }

        guard !isOverlay else { return }
        let newBackground: RGBAColor? = clearing ? .white : settings.strokeColor
        guard drawing.background != newBackground else { return }
        drawing.beginChange()
        drawing.background = newBackground
    }

    private func isMeaningful(_ shape: DrawShape) -> Bool {
        if shape.tool.isFreehand { return !shape.points.isEmpty }
        let rect = shape.dragRect
        return rect.width + rect.height > 3
    }

    /// Shift constrains lines to 45° steps and boxes to squares.
    private func constrainedPoint(from start: CGPoint, to point: CGPoint) -> CGPoint {
        guard NSEvent.modifierFlags.contains(.shift) else { return point }

        let dx = point.x - start.x, dy = point.y - start.y
        if settings.tool == .line || settings.tool == .arrow {
            let length = sqrt(dx * dx + dy * dy)
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side),
                       y: start.y + (dy < 0 ? -side : side))
    }

    // MARK: - Resize

    private func resizeChanged(_ handle: Handle, to point: CGPoint, bounds: CGRect) {
        if resizeOriginals == nil {
            resizeOriginals = Dictionary(uniqueKeysWithValues:
                drawing.selectedShapes.map { ($0.id, $0) })
            resizeStartRect = bounds
            drawing.beginChange()
        }
        guard let originals = resizeOriginals else { return }

        let target = handle.resized(resizeStartRect, to: point)
        guard target.width > 3, target.height > 3 else { return }

        for index in drawing.shapes.indices {
            guard var original = originals[drawing.shapes[index].id] else { continue }
            original.scale(from: resizeStartRect, to: target)
            drawing.shapes[index] = original
        }
    }

    private func resizeEnded() {
        resizeOriginals = nil
    }

    // MARK: - Text

    private func startEditing(at point: CGPoint) {
        editingID = nil
        editingText = ""
        editingOrigin = point
        isEditingText = true
        DispatchQueue.main.async { textFieldFocused = true }
    }

    private func startEditing(existing shape: DrawShape) {
        editingID = shape.id
        editingText = shape.text
        editingOrigin = shape.start
        settings.fontSize = shape.fontSize
        settings.strokeColor = shape.stroke
        isEditingText = true
        DispatchQueue.main.async { textFieldFocused = true }
    }

    private func commitText() {
        guard isEditingText else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingID = editingID

        isEditingText = false
        textFieldFocused = false
        editingID = nil
        editingText = ""

        if let existingID {
            guard let index = drawing.shapes.firstIndex(where: { $0.id == existingID }) else { return }
            drawing.beginChange()
            if trimmed.isEmpty {
                drawing.shapes.remove(at: index)
            } else {
                drawing.shapes[index].text = trimmed
                drawing.shapes[index].fontSize = settings.fontSize
                drawing.shapes[index].stroke = settings.strokeColor
            }
        } else if !trimmed.isEmpty {
            var shape = settings.makeShape(tool: .text, at: editingOrigin)
            shape.text = trimmed
            drawing.add(shape)
        }
    }
}
