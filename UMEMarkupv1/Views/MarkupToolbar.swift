import SwiftUI

struct MarkupToolbar: View {
    @Binding var tool: MarkupTool
    @Binding var color: Color
    var pageLabel: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MarkupTool.allCases) { item in
                        Button {
                            tool = item
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .foregroundStyle(tool == item ? Color.white : Color.primary)
                                .background(tool == item ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(tool == item ? [.isSelected] : [])
                    }
                }
            }

            Text(tool.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityHidden(true)

            Divider()
                .frame(height: 22)

            colorRow

            Spacer(minLength: 8)

            Text(pageLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button("Undo", systemImage: "arrow.uturn.backward") {
                onUndo()
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Undo")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var colorRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(MarkupPalette.swatches.enumerated()), id: \.offset) { _, swatch in
                Button {
                    color = swatch
                } label: {
                    Circle()
                        .fill(swatch)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: colorsMatch(color, swatch) ? 2 : 0.5)
                        }
                }
                .accessibilityLabel("Color")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func colorsMatch(_ lhs: Color, _ rhs: Color) -> Bool {
        lhs.hexString() == rhs.hexString()
    }
}

#Preview {
    MarkupToolbar(
        tool: .constant(.highlight),
        color: .constant(MarkupPalette.defaultHighlight),
        pageLabel: "Page 1 of 3",
        onUndo: {}
    )
}
