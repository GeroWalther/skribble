import AppKit
import CoreGraphics
import Foundation

/// One drawn object. Everything in a document is a `DrawShape`, which keeps undo,
/// selection, hit-testing and vector PDF export uniform across all tools.
struct DrawShape: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var tool: Tool
    var points: [CGPoint] = []
    var stroke: RGBAColor = .black
    var fill: RGBAColor? = nil
    var lineWidth: CGFloat = 4
    var dashed: Bool = false
    var text: String = ""
    var fontSize: CGFloat = 28

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    /// Normalized rect spanned by the first and last point (drag-defined tools).
    var dragRect: CGRect {
        let a = start, b = end
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    var font: NSFont {
        NSFont.systemFont(ofSize: max(fontSize, 4), weight: .semibold)
    }

    var textRect: CGRect {
        let measured = (text.isEmpty ? " " : text) as NSString
        let size = measured.boundingRect(
            with: CGSize(width: 4000, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).size
        return CGRect(origin: start, size: CGSize(width: ceil(size.width) + 2, height: ceil(size.height) + 2))
    }

    /// Bounds used for selection handles and hit tests, padded for stroke width.
    var bounds: CGRect {
        switch tool {
        case .text:
            return textRect
        case .pen, .highlighter, .eraser:
            guard let first = points.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let pad = lineWidth / 2 + 1
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -pad, dy: -pad)
        case .arrow:
            let pad = max(lineWidth * 2.5, 10)
            return dragRect.insetBy(dx: -pad, dy: -pad)
        default:
            let pad = lineWidth / 2 + 1
            return dragRect.insetBy(dx: -pad, dy: -pad)
        }
    }

    // MARK: - Path construction

    /// The stroked outline for this shape. `nil` for text, which is drawn by CoreText.
    func makePath() -> CGPath? {
        switch tool {
        case .text, .select, .bucket:
            return nil
        case .pen, .highlighter, .eraser:
            return DrawShape.smoothPath(points)
        case .line:
            let p = CGMutablePath()
            p.move(to: start); p.addLine(to: end)
            return p
        case .arrow:
            return DrawShape.arrowPath(from: start, to: end, lineWidth: lineWidth)
        case .rectangle:
            return CGPath(rect: dragRect, transform: nil)
        case .roundedRect:
            let r = dragRect
            let radius = min(min(r.width, r.height) * 0.22, max(lineWidth * 3, 14))
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: dragRect, transform: nil)
        case .triangle:
            let r = dragRect
            let p = CGMutablePath()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        case .star:
            return DrawShape.starPath(in: dragRect, points: 5)
        }
    }

    /// Freehand strokes are drawn as quadratic curves through the midpoints of
    /// consecutive samples, which removes the polygonal look of raw mouse input.
    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        guard pts.count > 2 else {
            path.move(to: first)
            if pts.count == 2 {
                path.addLine(to: pts[1])
            } else {
                // A single tap still needs to render as a dot.
                path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            }
            return path
        }
        path.move(to: first)
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                              y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    static func arrowPath(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)

        let dx = b.x - a.x, dy = b.y - a.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0.5 else { return path }

        let angle = atan2(dy, dx)
        let head = min(max(lineWidth * 4.5, 14), length)
        let spread = CGFloat.pi / 7

        path.move(to: b)
        path.addLine(to: CGPoint(x: b.x - cos(angle - spread) * head,
                                 y: b.y - sin(angle - spread) * head))
        path.move(to: b)
        path.addLine(to: CGPoint(x: b.x - cos(angle + spread) * head,
                                 y: b.y - sin(angle + spread) * head))
        return path
    }

    static func starPath(in rect: CGRect, points n: Int) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        let innerRatio: CGFloat = 0.4
        for i in 0..<(n * 2) {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(n)
            let f = i.isMultiple(of: 2) ? 1.0 : innerRatio
            let pt = CGPoint(x: center.x + cos(angle) * rx * f,
                             y: center.y + sin(angle) * ry * f)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Hit testing

    func hitTest(_ point: CGPoint, tolerance: CGFloat = 6) -> Bool {
        if tool == .text {
            return textRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
        guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
        guard let path = makePath() else { return false }

        if fill != nil, tool.isClosed, path.contains(point) { return true }

        let width = max(lineWidth, 1) + tolerance * 2
        let hitArea = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return hitArea.contains(point)
    }

    /// Hit test for the fill bucket. Unlike `hitTest`, a closed shape counts as
    /// solid even when it has no fill yet — otherwise you could only ever click
    /// its outline, which is not how a paint bucket is expected to behave.
    func fillHitTest(_ point: CGPoint, tolerance: CGFloat = 4) -> Bool {
        guard tool.isClosed, let path = makePath() else { return false }
        if path.contains(point) { return true }
        let width = max(lineWidth, 1) + tolerance * 2
        return path.copy(strokingWithWidth: width, lineCap: .round,
                         lineJoin: .round, miterLimit: 10).contains(point)
    }

    /// Whether any part of this shape falls inside a marquee rect.
    func intersects(_ rect: CGRect) -> Bool {
        guard bounds.intersects(rect) else { return false }
        if tool.isFreehand { return points.contains { rect.contains($0) } || rect.contains(bounds) }
        return true
    }

    // MARK: - Transforms

    mutating func translate(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }

    /// Rescales every point so that `from` maps onto `to`. Used by resize handles.
    mutating func scale(from source: CGRect, to target: CGRect) {
        let sx = source.width > 0.5 ? target.width / source.width : 1
        let sy = source.height > 0.5 ? target.height / source.height : 1
        points = points.map {
            CGPoint(x: target.minX + ($0.x - source.minX) * sx,
                    y: target.minY + ($0.y - source.minY) * sy)
        }
        if tool == .text {
            fontSize = max(6, fontSize * min(sx, sy))
        } else {
            lineWidth = max(0.5, lineWidth * min(sx, sy))
        }
    }
}
