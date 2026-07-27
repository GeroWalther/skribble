import AppKit
import SwiftUI

/// A codable sRGB color used by every shape so documents round-trip cleanly.
struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? NSColor.black
        self.init(r: Double(c.redComponent),
                  g: Double(c.greenComponent),
                  b: Double(c.blueComponent),
                  a: Double(c.alphaComponent))
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func withAlpha(_ newAlpha: Double) -> RGBAColor {
        RGBAColor(r: r, g: g, b: b, a: newAlpha)
    }

    /// Rough perceptual luminance — used to pick a readable outline for swatches.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    static let black = RGBAColor(r: 0, g: 0, b: 0)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)
    static let red = RGBAColor(r: 0.90, g: 0.13, b: 0.15)

    /// Windows-Paint-ish palette, ordered dark → light so it tiles nicely in a grid.
    static let palette: [RGBAColor] = [
        RGBAColor(r: 0.00, g: 0.00, b: 0.00),   // black
        RGBAColor(r: 0.50, g: 0.50, b: 0.50),   // gray
        RGBAColor(r: 0.75, g: 0.75, b: 0.75),   // silver
        RGBAColor(r: 1.00, g: 1.00, b: 1.00),   // white
        RGBAColor(r: 0.90, g: 0.13, b: 0.15),   // red
        RGBAColor(r: 1.00, g: 0.46, b: 0.09),   // orange
        RGBAColor(r: 1.00, g: 0.84, b: 0.00),   // yellow
        RGBAColor(r: 0.30, g: 0.75, b: 0.24),   // green
        RGBAColor(r: 0.00, g: 0.62, b: 0.60),   // teal
        RGBAColor(r: 0.10, g: 0.45, b: 0.95),   // blue
        RGBAColor(r: 0.36, g: 0.24, b: 0.78),   // indigo
        RGBAColor(r: 0.70, g: 0.20, b: 0.75),   // purple
        RGBAColor(r: 1.00, g: 0.40, b: 0.65),   // pink
        RGBAColor(r: 0.55, g: 0.35, b: 0.18),   // brown
        RGBAColor(r: 0.60, g: 0.80, b: 0.20),   // lime
        RGBAColor(r: 0.35, g: 0.83, b: 0.95),   // sky
        RGBAColor(r: 0.55, g: 0.00, b: 0.10),   // maroon
        RGBAColor(r: 0.05, g: 0.35, b: 0.15),   // forest
        RGBAColor(r: 0.05, g: 0.12, b: 0.40),   // navy
        RGBAColor(r: 0.96, g: 0.87, b: 0.70),   // sand
    ]

    /// High-contrast subset that reads well on top of arbitrary screen content.
    static let annotationPalette: [RGBAColor] = [
        RGBAColor(r: 0.90, g: 0.13, b: 0.15),
        RGBAColor(r: 1.00, g: 0.46, b: 0.09),
        RGBAColor(r: 1.00, g: 0.84, b: 0.00),
        RGBAColor(r: 0.30, g: 0.85, b: 0.30),
        RGBAColor(r: 0.10, g: 0.55, b: 1.00),
        RGBAColor(r: 0.70, g: 0.35, b: 1.00),
        RGBAColor(r: 1.00, g: 0.40, b: 0.70),
        RGBAColor(r: 0.20, g: 0.90, b: 0.85),
        RGBAColor(r: 1.00, g: 1.00, b: 1.00),
        RGBAColor(r: 0.00, g: 0.00, b: 0.00),
    ]
}
