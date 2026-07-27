import AppKit
import SwiftUI

/// Contents of a paint window: toolbar, zoomable page, status bar.
struct CanvasWorkspace: View {
    @ObservedObject var drawing: Drawing
    @ObservedObject var settings: ToolSettings
    @ObservedObject var app = AppState.shared

    @State private var zoom: CGFloat = 1
    @State private var showCanvasSizeSheet = false
    @State private var pendingWidth = ""
    @State private var pendingHeight = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            page
            Divider()
            statusBar
        }
        .sheet(isPresented: $showCanvasSizeSheet) { canvasSizeSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(Tool.drawingTools) { tool in
                        ToolIconButton(systemImage: tool.systemImage,
                                       help: tool.title,
                                       isActive: settings.tool == tool) {
                            settings.tool = tool
                        }
                    }
                }

                Divider().frame(height: 24)

                WidthPicker(width: $settings.lineWidth)

                Divider().frame(height: 24)

                Toggle(isOn: $settings.useFill) {
                    Label("Fill", systemImage: "paintbrush.fill")
                }
                .toggleStyle(.button)
                .help("Fill closed shapes with the fill color")

                Toggle(isOn: $settings.dashed) {
                    Label("Dashed", systemImage: "line.3.horizontal.decrease")
                }
                .toggleStyle(.button)
                .help("Dashed outlines")

                Spacer(minLength: 8)

                ToolIconButton(systemImage: "arrow.uturn.backward", help: "Undo (⌘Z)") {
                    drawing.undo()
                }
                .disabled(!drawing.canUndo)
                .opacity(drawing.canUndo ? 1 : 0.35)

                ToolIconButton(systemImage: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") {
                    drawing.redo()
                }
                .disabled(!drawing.canRedo)
                .opacity(drawing.canRedo ? 1 : 0.35)

                ToolIconButton(systemImage: "trash", help: "Clear canvas") {
                    drawing.clear()
                }

                Divider().frame(height: 24)

                Button {
                    OverlayController.shared.toggle()
                } label: {
                    Label("Draw on Screen", systemImage: "rectangle.dashed.and.paperclip")
                }
                .help("Annotate anything on screen (⌃⌥⌘D)")
            }

            HStack(spacing: 10) {
                Text(settings.tool == .bucket ? "Fill" : "Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)

                currentColorWell(color: settings.strokeColor) { picked in
                    settings.applyPaletteColor(picked, to: drawing)
                }

                colorGrid { picked in
                    settings.applyPaletteColor(picked, to: drawing)
                }

                Spacer(minLength: 4)

                if settings.tool == .text {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.fontSize, in: 10...120)
                        .frame(width: 110)
                    Text("\(Int(settings.fontSize))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func currentColorWell(color: RGBAColor, onPick: @escaping (RGBAColor) -> Void) -> some View {
        // NSColorPanel via SwiftUI's ColorPicker, bridged through RGBAColor.
        ColorPicker("", selection: Binding(
            get: { color.color },
            set: { newValue in
                let ns = NSColor(newValue)
                onPick(RGBAColor(ns))
            }
        ), supportsOpacity: true)
        .labelsHidden()
        .frame(width: 44)
    }

    private func colorGrid(onPick: @escaping (RGBAColor) -> Void) -> some View {
        let columns = Array(repeating: GridItem(.fixed(18), spacing: 3), count: 10)
        return LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(RGBAColor.palette.enumerated()), id: \.offset) { _, color in
                ColorSwatch(color: color, isSelected: color == settings.strokeColor) {
                    onPick(color)
                }
            }
        }
        .frame(width: 10 * 18 + 9 * 3)
    }

    // MARK: - Page

    private var page: some View {
        GeometryReader { _ in
            ScrollView([.horizontal, .vertical]) {
                DrawCanvas(drawing: drawing, settings: settings)
                    .frame(width: drawing.canvasSize.width, height: drawing.canvasSize.height)
                    .background(
                        Rectangle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    )
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: drawing.canvasSize.width * zoom,
                           height: drawing.canvasSize.height * zoom)
                    .padding(40)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(settings.tool.title, systemImage: settings.tool.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(Int(drawing.canvasSize.width)) × \(Int(drawing.canvasSize.height))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Resize…") {
                pendingWidth = String(Int(drawing.canvasSize.width))
                pendingHeight = String(Int(drawing.canvasSize.height))
                showCanvasSizeSheet = true
            }
            .buttonStyle(.link)
            .font(.caption)

            Text("\(drawing.shapes.count) object\(drawing.shapes.count == 1 ? "" : "s")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button { zoom = max(0.1, zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain)
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42)
            Button { zoom = min(6, zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain)
            Button("Fit") { zoom = 1 }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var canvasSizeSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canvas Size").font(.headline)
            HStack {
                TextField("Width", text: $pendingWidth).frame(width: 80)
                Text("×")
                TextField("Height", text: $pendingHeight).frame(width: 80)
                Text("px").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showCanvasSizeSheet = false }
                Button("Apply") {
                    if let w = Double(pendingWidth), let h = Double(pendingHeight), w > 20, h > 20 {
                        drawing.canvasSize = CGSize(width: w, height: h)
                        drawing.hasUnsavedChanges = true
                    }
                    showCanvasSizeSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
