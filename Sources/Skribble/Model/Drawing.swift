import AppKit
import Combine
import Foundation

/// On-disk document format for `.skribble` files.
struct DocumentFile: Codable {
    var version: Int = 1
    var canvasSize: CGSize
    var background: RGBAColor?
    var shapes: [DrawShape]
}

/// The shape list plus selection and undo history. One instance backs each canvas
/// window; a separate shared instance backs the screen-annotation overlay.
@MainActor
final class Drawing: ObservableObject {
    @Published var shapes: [DrawShape] = []
    @Published var selection: Set<UUID> = []
    @Published var canvasSize: CGSize
    @Published var background: RGBAColor?

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    @Published var fileURL: URL?
    @Published var hasUnsavedChanges = false

    /// The bucket can repaint the page, so history captures the background too.
    private struct Snapshot {
        var shapes: [DrawShape]
        var background: RGBAColor?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let historyLimit = 200

    private var currentSnapshot: Snapshot {
        Snapshot(shapes: shapes, background: background)
    }

    init(canvasSize: CGSize = CGSize(width: 1400, height: 900), background: RGBAColor? = .white) {
        self.canvasSize = canvasSize
        self.background = background
    }

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var selectedShapes: [DrawShape] {
        shapes.filter { selection.contains($0.id) }
    }

    var selectionBounds: CGRect? {
        let sel = selectedShapes
        guard let first = sel.first else { return nil }
        return sel.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
    }

    // MARK: - Undo

    /// Call immediately *before* mutating `shapes`.
    func beginChange() {
        undoStack.append(currentSnapshot)
        if undoStack.count > historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        hasUnsavedChanges = true
        refreshFlags()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
        shapes = snapshot.shapes
        background = snapshot.background
        selection = selection.filter { id in shapes.contains { $0.id == id } }
        hasUnsavedChanges = true
        refreshFlags()
    }

    private func refreshFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: - Editing

    func add(_ shape: DrawShape) {
        beginChange()
        shapes.append(shape)
    }

    func clear() {
        guard !shapes.isEmpty else { return }
        beginChange()
        shapes.removeAll()
        selection.removeAll()
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        beginChange()
        shapes.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func selectAll() {
        selection = Set(shapes.map(\.id))
    }

    func bringSelectionToFront() {
        guard !selection.isEmpty else { return }
        beginChange()
        let moved = shapes.filter { selection.contains($0.id) }
        shapes.removeAll { selection.contains($0.id) }
        shapes.append(contentsOf: moved)
    }

    func sendSelectionToBack() {
        guard !selection.isEmpty else { return }
        beginChange()
        let moved = shapes.filter { selection.contains($0.id) }
        shapes.removeAll { selection.contains($0.id) }
        shapes.insert(contentsOf: moved, at: 0)
    }

    /// Topmost shape under `point`, honoring draw order.
    func shape(at point: CGPoint, tolerance: CGFloat = 6) -> DrawShape? {
        shapes.reversed().first { $0.hitTest(point, tolerance: tolerance) }
    }

    /// Object eraser: removes any shape touched by the eraser tip.
    @discardableResult
    func erase(at point: CGPoint, radius: CGFloat) -> Bool {
        let victims = shapes.filter { $0.hitTest(point, tolerance: radius) }.map(\.id)
        guard !victims.isEmpty else { return false }
        shapes.removeAll { victims.contains($0.id) }
        selection.subtract(victims)
        hasUnsavedChanges = true
        return true
    }

    func applyToSelection(_ transform: (inout DrawShape) -> Void) {
        guard !selection.isEmpty else { return }
        beginChange()
        for index in shapes.indices where selection.contains(shapes[index].id) {
            transform(&shapes[index])
        }
    }

    // MARK: - Persistence

    func documentFile() -> DocumentFile {
        DocumentFile(canvasSize: canvasSize, background: background, shapes: shapes)
    }

    func load(_ file: DocumentFile, url: URL?) {
        undoStack.removeAll()
        redoStack.removeAll()
        shapes = file.shapes
        canvasSize = file.canvasSize
        background = file.background
        selection.removeAll()
        fileURL = url
        hasUnsavedChanges = false
        refreshFlags()
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(documentFile()).write(to: url, options: .atomic)
        fileURL = url
        hasUnsavedChanges = false
    }

    static func read(from url: URL) throws -> DocumentFile {
        try JSONDecoder().decode(DocumentFile.self, from: Data(contentsOf: url))
    }
}
