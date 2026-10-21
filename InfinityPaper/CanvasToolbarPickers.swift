import SwiftUI
import UIKit

struct CanvasToolbarPickerPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let isPad: Bool
    @ViewBuilder var content: () -> Content

    private var fill: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(white: 0.12, alpha: 0.96)
            } else {
                UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 0.98)
            }
        })
    }

    private var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        content()
            .padding(.horizontal, isPad ? 18 : 14)
            .padding(.vertical, isPad ? 14 : 12)
            .background(
                RoundedRectangle(cornerRadius: isPad ? 18 : 16, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: isPad ? 18 : 16, style: .continuous)
                            .stroke(stroke, lineWidth: 0.5)
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: isPad ? 12 : 8, y: isPad ? 4 : 3)
    }
}

// MARK: - Color popover body

struct CanvasToolbarColorPickerBody: View {
    let colors: [UIColor]
    let selectedIndex: Int
    let isPad: Bool
    let onPick: (Int) -> Void

    private var swatch: CGFloat { isPad ? 30 : 26 }
    private var spacing: CGFloat { isPad ? 12 : 10 }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { idx, ui in
                        Button {
                            onPick(idx)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(uiColor: ui))
                                    .frame(width: swatch, height: swatch)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                    )
                                if idx == selectedIndex {
                                    Circle()
                                        .stroke(Color.primary.opacity(0.55), lineWidth: 2)
                                        .frame(width: swatch + 6, height: swatch + 6)
                                }
                            }
                            .frame(width: swatch + 10, height: swatch + 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(CanvasBrush.colorName(at: idx)))
                        .accessibilityAddTraits(idx == selectedIndex ? .isSelected : [])
                    }
                }
            }
            Image(systemName: "chevron.right.circle.fill")
                .font(.system(size: isPad ? 17 : 15, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.45))
                .padding(.trailing, 2)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: isPad ? 360 : 260)
    }
}

// MARK: - Line width popover body

struct CanvasToolbarLineWidthPickerBody: View {
    let presets: [CGFloat]
    let selectedIndex: Int
    let isPad: Bool
    let sampleTint: Color
    let onPick: (Int) -> Void

    private var cellW: CGFloat { isPad ? 48 : 42 }
    private var barWidth: CGFloat { isPad ? 36 : 32 }

    var body: some View {
        HStack(spacing: isPad ? 14 : 10) {
            ForEach(Array(presets.enumerated()), id: \.offset) { idx, width in
                Button {
                    onPick(idx)
                } label: {
                    let displayH = min(max(width * 1.05, 2), 8)
                    VStack(spacing: 6) {
                        Capsule(style: .continuous)
                            .fill(sampleTint)
                            .frame(width: barWidth, height: displayH)
                        if isPad {
                            Text(String(format: "%.1f", width))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: cellW, height: isPad ? 52 : 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(idx == selectedIndex ? 0.08 : 0))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(idx == selectedIndex ? 0.35 : 0), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(widthAccessibilityLabel(for: width))
                .accessibilityValue(Text("\(String(format: "%.1f", width)) pt"))
                .accessibilityAddTraits(idx == selectedIndex ? .isSelected : [])
            }
        }
    }

    private func widthAccessibilityLabel(for width: CGFloat) -> Text {
        switch width {
        case ..<2:
            return Text(String(localized: "toolbar.width_a11y_thin"))
        case ..<3.5:
            return Text(String(localized: "toolbar.width_a11y_medium"))
        case ..<5:
            return Text(String(localized: "toolbar.width_a11y_bold"))
        default:
            return Text(String(localized: "toolbar.width_a11y_heavy"))
        }
    }
}
