#!/usr/bin/env swift
// Generates Skribble's app icon as an .iconset directory of PNGs.
// Usage: swift tools/make-icon.swift <output.iconset>

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func drawIcon(size: CGFloat, into ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let s = size / 1024  // design at 1024pt, scale everything down

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Rounded-square backdrop with a diagonal gradient.
    let inset = 44 * s
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = 190 * s
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(srgbRed: 0.24, green: 0.28, blue: 0.62, alpha: 1),
        CGColor(srgbRed: 0.46, green: 0.24, blue: 0.72, alpha: 1),
        CGColor(srgbRed: 0.72, green: 0.25, blue: 0.55, alpha: 1),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY),
                           options: [])
    ctx.restoreGState()

    // A sweeping brush stroke.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let stroke = CGMutablePath()
    stroke.move(to: CGPoint(x: 250 * s, y: 380 * s))
    stroke.addCurve(to: CGPoint(x: 545 * s, y: 690 * s),
                    control1: CGPoint(x: 330 * s, y: 660 * s),
                    control2: CGPoint(x: 430 * s, y: 700 * s))
    stroke.addCurve(to: CGPoint(x: 790 * s, y: 400 * s),
                    control1: CGPoint(x: 690 * s, y: 680 * s),
                    control2: CGPoint(x: 700 * s, y: 430 * s))
    ctx.addPath(stroke)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.97))
    ctx.setLineWidth(78 * s)
    ctx.strokePath()
    ctx.restoreGState()

    // A small accent arrow, nodding at the annotation mode.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let arrow = CGMutablePath()
    let tip = CGPoint(x: 782 * s, y: 398 * s)
    arrow.move(to: CGPoint(x: 640 * s, y: 250 * s))
    arrow.addLine(to: tip)
    arrow.move(to: tip)
    arrow.addLine(to: CGPoint(x: 700 * s, y: 392 * s))
    arrow.move(to: tip)
    arrow.addLine(to: CGPoint(x: 776 * s, y: 316 * s))
    ctx.addPath(arrow)
    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 0.83, blue: 0.25, alpha: 1))
    ctx.setLineWidth(46 * s)
    ctx.strokePath()
    ctx.restoreGState()
}

func writePNG(pixelSize: Int, to url: URL) {
    guard let ctx = CGContext(data: nil,
                              width: pixelSize,
                              height: pixelSize,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return
    }
    drawIcon(size: CGFloat(pixelSize), into: ctx)
    guard let image = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

// The set of sizes `iconutil` expects.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    writePNG(pixelSize: variant.pixels, to: outputURL.appendingPathComponent(variant.name))
}
print("Wrote \(variants.count) icon images to \(outputURL.path)")
