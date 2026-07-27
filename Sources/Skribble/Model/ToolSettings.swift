import Combine
import Foundation

/// Current tool and its styling. Each canvas window owns one; the overlay owns
/// its own so annotation defaults (thick red) survive independently.
///
/// There is a single active color. Filling is done afterwards with the bucket
/// tool rather than by maintaining a second color.
@MainActor
final class ToolSettings: ObservableObject {
    @Published var tool: Tool
    @Published var strokeColor: RGBAColor
    @Published var useFill: Bool
    @Published var lineWidth: CGFloat
    @Published var fontSize: CGFloat
    @Published var dashed: Bool

    init(tool: Tool = .pen,
         strokeColor: RGBAColor = .black,
         useFill: Bool = false,
         lineWidth: CGFloat = 4,
         fontSize: CGFloat = 28,
         dashed: Bool = false) {
        self.tool = tool
        self.strokeColor = strokeColor
        self.useFill = useFill
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.dashed = dashed
    }

    static let widthPresets: [CGFloat] = [1, 2, 4, 8, 14, 22]

    /// Picks a color, mirroring it onto the current selection. With the bucket
    /// active the choice repaints the selection's fill instead of its outline,
    /// which is what the tool is for.
    func applyPaletteColor(_ color: RGBAColor, to drawing: Drawing) {
        strokeColor = color
        let fillMode = tool == .bucket
        drawing.applyToSelection { shape in
            if fillMode {
                if shape.tool.isClosed { shape.fill = color }
            } else {
                shape.stroke = color
            }
        }
    }

    /// Highlighter always uses a fat, soft nib regardless of the stroke slider.
    func effectiveLineWidth(for tool: Tool) -> CGFloat {
        switch tool {
        case .highlighter: return max(lineWidth * 3, 14)
        case .eraser: return max(lineWidth * 3, 16)
        default: return lineWidth
        }
    }

    func makeShape(tool: Tool, at point: CGPoint) -> DrawShape {
        DrawShape(
            tool: tool,
            points: [point],
            stroke: tool == .highlighter ? strokeColor.withAlpha(1) : strokeColor,
            fill: (tool.isClosed && useFill) ? strokeColor : nil,
            lineWidth: effectiveLineWidth(for: tool),
            dashed: dashed && tool != .highlighter,
            text: "",
            fontSize: fontSize
        )
    }
}
