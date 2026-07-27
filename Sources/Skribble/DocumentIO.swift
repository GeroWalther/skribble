import AppKit
import UniformTypeIdentifiers

/// Open/save for `.skribble` documents (JSON shape lists).
enum DocumentIO {
    static let fileExtension = "skribble"

    static var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .json
    }

    @MainActor
    @discardableResult
    static func save(drawing: Drawing, saveAs: Bool) -> Bool {
        var target = drawing.fileURL

        if saveAs || target == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [contentType]
            panel.allowsOtherFileTypes = true
            panel.nameFieldStringValue = "\(drawing.displayName).\(fileExtension)"
            panel.canCreateDirectories = true
            panel.title = "Save Drawing"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url
        }

        guard let url = target else { return false }
        do {
            try drawing.save(to: url)
            AppDelegate.shared?.refreshTitles()
            return true
        } catch {
            Exporter.presentError(error)
            return false
        }
    }

    @MainActor
    static func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType, .json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Open Drawing"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            openDocument(at: url)
        }
    }

    @MainActor
    static func openDocument(at url: URL) {
        do {
            let file = try Drawing.read(from: url)
            let drawing = Drawing()
            drawing.load(file, url: url)
            AppDelegate.shared?.newWindow(with: drawing)
        } catch {
            Exporter.presentError(error)
        }
    }
}
