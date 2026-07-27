import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg, pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .pdf: return "PDF"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .pdf: return .pdf
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .pdf: return "pdf"
        }
    }

    /// JPEG has no alpha channel, so it always needs an opaque backdrop.
    var requiresOpaqueBackground: Bool { self == .jpeg }
}

enum ExportError: LocalizedError {
    case contextCreationFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: return "Could not create a graphics context for export."
        case .encodingFailed: return "Could not encode the image data."
        }
    }
}

enum Exporter {

    /// Rasterizes the drawing. `underlay` is composited beneath the shapes and is
    /// used for "screenshot + annotations" exports.
    static func makeImage(shapes: [DrawShape],
                          size: CGSize,
                          background: RGBAColor?,
                          underlay: CGImage? = nil,
                          scale: CGFloat = 2) throws -> CGImage {
        let pixelWidth = max(Int((size.width * scale).rounded()), 1)
        let pixelHeight = max(Int((size.height * scale).rounded()), 1)

        guard let ctx = CGContext(data: nil,
                                  width: pixelWidth,
                                  height: pixelHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ExportError.contextCreationFailed }

        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        Renderer.flip(ctx, height: size.height)

        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        if let underlay {
            ctx.saveGState()
            // The underlay is a normal y-up CGImage, so undo the flip while drawing it.
            Renderer.flip(ctx, height: size.height)
            ctx.draw(underlay, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }

        Renderer.render(shapes: shapes, size: size, background: nil, in: ctx)

        guard let image = ctx.makeImage() else { throw ExportError.encodingFailed }
        return image
    }

    static func pngData(shapes: [DrawShape],
                        size: CGSize,
                        background: RGBAColor?,
                        underlay: CGImage? = nil,
                        scale: CGFloat = 2) throws -> Data {
        let image = try makeImage(shapes: shapes, size: size, background: background,
                                  underlay: underlay, scale: scale)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    static func jpegData(shapes: [DrawShape],
                         size: CGSize,
                         background: RGBAColor?,
                         underlay: CGImage? = nil,
                         scale: CGFloat = 2,
                         quality: CGFloat = 0.92) throws -> Data {
        let image = try makeImage(shapes: shapes, size: size,
                                  background: background ?? .white,
                                  underlay: underlay, scale: scale)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg,
                                            properties: [.compressionFactor: quality]) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    /// Vector PDF — shapes stay resolution-independent unless an underlay bitmap
    /// is supplied.
    static func pdfData(shapes: [DrawShape],
                        size: CGSize,
                        background: RGBAColor?,
                        underlay: CGImage? = nil) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw ExportError.contextCreationFailed
        }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.contextCreationFailed
        }

        ctx.beginPDFPage(nil)
        if let underlay {
            ctx.draw(underlay, in: mediaBox)
        }
        Renderer.flip(ctx, height: size.height)
        Renderer.render(shapes: shapes, size: size, background: background, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()

        return data as Data
    }

    static func data(format: ExportFormat,
                     shapes: [DrawShape],
                     size: CGSize,
                     background: RGBAColor?,
                     underlay: CGImage? = nil,
                     scale: CGFloat = 2) throws -> Data {
        switch format {
        case .png:
            return try pngData(shapes: shapes, size: size, background: background,
                               underlay: underlay, scale: scale)
        case .jpeg:
            return try jpegData(shapes: shapes, size: size, background: background,
                                underlay: underlay, scale: scale)
        case .pdf:
            return try pdfData(shapes: shapes, size: size, background: background,
                               underlay: underlay)
        }
    }

    // MARK: - Panels & clipboard

    @MainActor
    static func exportWithPanel(format: ExportFormat,
                                shapes: [DrawShape],
                                size: CGSize,
                                background: RGBAColor?,
                                underlay: CGImage? = nil,
                                suggestedName: String) {
        // Writing an empty file silently is the worst outcome — it reads as a
        // broken exporter rather than an empty drawing.
        guard !shapes.isEmpty || underlay != nil else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = """
                This drawing is empty, so the exported file would be blank.

                If you meant to export screen annotations, make sure the drawing you \
                want is the one in front — exports follow the focused window.
                """
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.title = "Export as \(format.title)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bg = format.requiresOpaqueBackground ? (background ?? .white) : background
            let payload = try data(format: format, shapes: shapes, size: size,
                                   background: bg, underlay: underlay)
            try payload.write(to: url, options: .atomic)
        } catch {
            presentError(error)
        }
    }

    @MainActor
    static func copyToPasteboard(shapes: [DrawShape],
                                 size: CGSize,
                                 background: RGBAColor?,
                                 underlay: CGImage? = nil) {
        do {
            let png = try pngData(shapes: shapes, size: size, background: background,
                                  underlay: underlay)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
        } catch {
            presentError(error)
        }
    }

    @MainActor
    static func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
