import SwiftUI

enum OverlayExportAction {
    case copyAnnotations
    case saveAnnotationsPNG
    case saveAnnotationsPDF
    case saveScreenshotPNG
    case saveScreenshotJPEG
    case saveScreenshotPDF
}

/// Full-screen annotation surface. Sits in a transparent panel above everything.
struct OverlayRootView: View {
    @ObservedObject var drawing: Drawing
    @ObservedObject var settings: ToolSettings
    @ObservedObject var app = AppState.shared

    var body: some View {
        ZStack {
            if app.dimLevel > 0 {
                Color.black.opacity(app.dimLevel)
                    .allowsHitTesting(false)
            }
            DrawCanvas(drawing: drawing, settings: settings, isOverlay: true)
        }
        .ignoresSafeArea()
    }
}

/// The slide-in tool palette that appears when the pointer hits the left edge.
struct SidebarView: View {
    @ObservedObject var settings: ToolSettings
    @ObservedObject var drawing: Drawing
    @ObservedObject var app = AppState.shared

    var onExport: (OverlayExportAction) -> Void
    var onExit: () -> Void
    var onHoverChange: (Bool) -> Void

    static let width: CGFloat = 100

    private static let tools: [Tool] = [
        .pen, .highlighter, .line, .arrow,
        .rectangle, .roundedRect, .ellipse, .triangle,
        .star, .bucket, .text, .eraser,
        .select,
    ]

    private let twoColumns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 2)
    private let threeColumns = Array(repeating: GridItem(.fixed(24), spacing: 5), count: 3)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                toolsSection
                separator
                colorsSection
                separator
                widthSection
                separator
                modifiersSection
                separator
                historySection
                separator
                screenSection
                separator
                outputSection
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 18, x: 4, y: 4)
        )
        .environment(\.colorScheme, .dark)
        .onHover { onHoverChange($0) }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    private var toolsSection: some View {
        LazyVGrid(columns: twoColumns, spacing: 4) {
            ForEach(Self.tools) { tool in
                ToolIconButton(systemImage: tool.systemImage,
                               help: tool.title,
                               isActive: settings.tool == tool,
                               isCompact: true,
                               tint: .white) {
                    settings.tool = tool
                }
            }
        }
    }

    private var colorsSection: some View {
        LazyVGrid(columns: threeColumns, spacing: 5) {
            ForEach(Array(RGBAColor.annotationPalette.enumerated()), id: \.offset) { _, color in
                ColorSwatch(color: color,
                            isSelected: color == settings.strokeColor,
                            side: 24) {
                    settings.applyPaletteColor(color, to: drawing)
                }
            }
        }
    }

    private var widthSection: some View {
        LazyVGrid(columns: threeColumns, spacing: 5) {
            ForEach(ToolSettings.widthPresets, id: \.self) { preset in
                Button {
                    settings.lineWidth = preset
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: min(preset + 2, 16), height: min(preset + 2, 16))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.lineWidth == preset ? Color.accentColor : Color.white.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(Int(preset)) pt")
            }
        }
    }

    private var modifiersSection: some View {
        HStack(spacing: 4) {
            ToolIconButton(systemImage: "paintbrush.fill",
                           help: "Fill shapes",
                           isActive: settings.useFill,
                           isCompact: true,
                           tint: .white) {
                settings.useFill.toggle()
            }
            ToolIconButton(systemImage: "line.3.horizontal.decrease",
                           help: "Dashed outlines",
                           isActive: settings.dashed,
                           isCompact: true,
                           tint: .white) {
                settings.dashed.toggle()
            }
        }
    }

    private var historySection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ToolIconButton(systemImage: "arrow.uturn.backward",
                               help: "Undo (⌘Z)", isCompact: true, tint: .white) {
                    drawing.undo()
                }
                .opacity(drawing.canUndo ? 1 : 0.3)

                ToolIconButton(systemImage: "arrow.uturn.forward",
                               help: "Redo (⇧⌘Z)", isCompact: true, tint: .white) {
                    drawing.redo()
                }
                .opacity(drawing.canRedo ? 1 : 0.3)
            }
            ToolIconButton(systemImage: "trash",
                           help: "Erase all annotations", isCompact: true, tint: .white) {
                drawing.clear()
            }
        }
    }

    private var screenSection: some View {
        VStack(spacing: 4) {
            ToolIconButton(systemImage: app.clickThrough ? "hand.tap" : "hand.raised.slash",
                           help: app.clickThrough
                               ? "Click-through is ON — clicks reach the apps below"
                               : "Click-through is OFF — the overlay captures the mouse",
                           isActive: app.clickThrough,
                           isCompact: true,
                           tint: .white) {
                app.clickThrough.toggle()
            }

            ToolIconButton(systemImage: dimIcon,
                           help: "Dim the screen behind your annotations",
                           isActive: app.dimLevel > 0,
                           isCompact: true,
                           tint: .white) {
                app.dimLevel = app.dimLevel == 0 ? 0.25 : (app.dimLevel == 0.25 ? 0.5 : 0)
            }
        }
    }

    private var dimIcon: String {
        switch app.dimLevel {
        case 0: return "sun.max"
        case 0.25: return "sun.min"
        default: return "moon"
        }
    }

    private var outputSection: some View {
        VStack(spacing: 4) {
            Menu {
                Button("Copy Annotations") { onExport(.copyAnnotations) }
                Divider()
                Button("Save Annotations as PNG…") { onExport(.saveAnnotationsPNG) }
                Button("Save Annotations as PDF…") { onExport(.saveAnnotationsPDF) }
                Divider()
                Button("Save Screen + Annotations as PNG…") { onExport(.saveScreenshotPNG) }
                Button("Save Screen + Annotations as JPEG…") { onExport(.saveScreenshotJPEG) }
                Button("Save Screen + Annotations as PDF…") { onExport(.saveScreenshotPDF) }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 34, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.10)))
            .help("Export")

            ToolIconButton(systemImage: "xmark",
                           help: "Exit screen drawing (Esc)",
                           isCompact: true,
                           tint: .white) {
                onExit()
            }
        }
    }
}
