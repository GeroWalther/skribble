import SwiftUI

/// Square icon button used by both toolbars.
struct ToolIconButton: View {
    let systemImage: String
    let help: String
    var isActive: Bool = false
    var isCompact: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    private var side: CGFloat { isCompact ? 30 : 32 }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isCompact ? 14 : 13, weight: .medium))
                .frame(width: side, height: side)
                .foregroundStyle(isActive ? Color.white : (tint ?? Color.primary))
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isActive ? Color.accentColor
                              : (hovering ? Color.primary.opacity(0.12) : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A single color swatch with a selection ring.
struct ColorSwatch: View {
    let color: RGBAColor
    let isSelected: Bool
    var side: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.color)
                .frame(width: side, height: side)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(color.luminance > 0.85 ? Color.primary.opacity(0.35)
                                                             : Color.black.opacity(0.18),
                                      lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                        .padding(-2.5)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Stroke-width picker rendered as dots of the actual weight.
struct WidthPicker: View {
    @Binding var width: CGFloat
    var dark: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ToolSettings.widthPresets, id: \.self) { preset in
                Button {
                    width = preset
                } label: {
                    Circle()
                        .fill(dark ? Color.white : Color.primary)
                        .frame(width: min(preset + 2, 16), height: min(preset + 2, 16))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(width == preset ? Color.accentColor.opacity(dark ? 0.9 : 0.28)
                                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(Int(preset)) pt")
            }
        }
    }
}
