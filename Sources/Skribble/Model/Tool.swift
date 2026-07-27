import Foundation

enum Tool: String, CaseIterable, Identifiable, Codable {
    case select
    case pen
    case highlighter
    case eraser
    case line
    case arrow
    case rectangle
    case roundedRect
    case ellipse
    case triangle
    case star
    case bucket
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .pen: return "Pencil"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .roundedRect: return "Rounded Rectangle"
        case .ellipse: return "Ellipse"
        case .triangle: return "Triangle"
        case .star: return "Star"
        case .bucket: return "Fill with Color"
        case .text: return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .roundedRect: return "app"
        case .ellipse: return "oval"
        case .triangle: return "triangle"
        case .star: return "star"
        case .bucket: return "drop.fill"
        case .text: return "textformat"
        }
    }

    /// Tools that produce a closed outline and can therefore take a fill color.
    var isClosed: Bool {
        switch self {
        case .rectangle, .roundedRect, .ellipse, .triangle, .star: return true
        default: return false
        }
    }

    /// Tools defined by a drag from one corner/endpoint to another.
    var isDragDefined: Bool {
        switch self {
        case .line, .arrow, .rectangle, .roundedRect, .ellipse, .triangle, .star: return true
        default: return false
        }
    }

    /// Freehand tools that accumulate every sampled point.
    var isFreehand: Bool { self == .pen || self == .highlighter }

    /// Tools that act on a single click rather than a drag.
    var isClickAction: Bool { self == .bucket || self == .text }

    /// Order used in the toolbars.
    static let drawingTools: [Tool] = [
        .pen, .highlighter, .line, .arrow,
        .rectangle, .roundedRect, .ellipse, .triangle,
        .star, .bucket, .text, .eraser, .select,
    ]
}
