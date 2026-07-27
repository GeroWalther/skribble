import AppKit
import CoreGraphics
import CoreText

/// Single Core Graphics drawing path shared by the live canvas, the screen
/// overlay and every exporter, so what you see is exactly what you export.
///
/// All rendering assumes a **top-left origin, y-down** coordinate system — the
/// same convention SwiftUI uses — so exporters must flip their context first.
enum Renderer {

    static func render(shapes: [DrawShape],
                       size: CGSize,
                       background: RGBAColor?,
                       in ctx: CGContext) {
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        for shape in shapes {
            draw(shape, in: ctx)
        }
    }

    static func draw(_ shape: DrawShape, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setShouldAntialias(true)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if shape.tool == .text {
            drawText(shape, in: ctx)
            return
        }

        guard let path = shape.makePath() else { return }

        // The highlighter multiplies so underlying content stays readable.
        if shape.tool == .highlighter {
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.38)
        }

        if let fill = shape.fill, shape.tool.isClosed {
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }

        guard shape.lineWidth > 0 else { return }
        ctx.addPath(path)
        ctx.setStrokeColor(shape.stroke.cgColor)
        ctx.setLineWidth(shape.lineWidth)
        if shape.dashed {
            let dash = max(shape.lineWidth * 2.5, 4)
            ctx.setLineDash(phase: 0, lengths: [dash, dash])
        }
        ctx.strokePath()
    }

    private static func drawText(_ shape: DrawShape, in ctx: CGContext) {
        guard !shape.text.isEmpty else { return }
        let font = shape.font
        let lineHeight = font.ascender - font.descender + font.leading

        ctx.saveGState()
        // The context is y-down; flipping the text matrix keeps glyphs upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        var baseline = shape.start.y + font.ascender
        for line in shape.text.components(separatedBy: "\n") {
            if !line.isEmpty {
                let attributed = NSAttributedString(string: line, attributes: [
                    .font: font,
                    .foregroundColor: shape.stroke.nsColor,
                ])
                let ctLine = CTLineCreateWithAttributedString(attributed)
                ctx.textPosition = CGPoint(x: shape.start.x, y: baseline)
                CTLineDraw(ctLine, ctx)
            }
            baseline += lineHeight
        }
        ctx.restoreGState()
    }

    /// Flips `ctx` from Core Graphics' y-up default into the y-down space the
    /// renderer expects.
    static func flip(_ ctx: CGContext, height: CGFloat) {
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)
    }
}
