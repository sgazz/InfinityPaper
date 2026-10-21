import SwiftUI
import UIKit

enum CanvasToolbarMoreCommand: String, CaseIterable {
    case drawings = "toolbar.my_drawings"
    case clear = "toolbar.infinity_clear"
    case newDrawing = "toolbar.infinity_new_space"
    case center = "toolbar.infinity_center"
    case zoomIn = "toolbar.infinity_zoom_in"
    case zoomOut = "toolbar.infinity_zoom_out"
    case resetView = "toolbar.infinity_reset_view"
    case fitContent = "toolbar.infinity_fit_content"
    case focus = "toolbar.infinity_focus"

    var isDestructive: Bool { self == .clear }
    var requiresCanvas: Bool { self != .drawings }
    var icon: String {
        switch self {
        case .drawings: return "square.grid.2x2"
        case .clear: return "trash"
        case .newDrawing: return "square.dashed"
        case .center: return "scope"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .resetView: return "arrow.counterclockwise"
        case .fitContent: return "arrow.up.left.and.down.right.magnifyingglass"
        case .focus: return "moon.stars"
        }
    }
}

struct CanvasToolbarMoreMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    let isPad: Bool
    let canvasReady: Bool
    let onCommand: (CanvasToolbarMoreCommand) -> Void

    private var fill: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(white: 0.11, alpha: 0.97)
            } else {
                UIColor(red: 0.99, green: 0.98, blue: 0.99, alpha: 0.98)
            }
        })
    }

    private var stroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.07)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CanvasToolbarMoreCommand.allCases.enumerated()), id: \.offset) { index, item in
                if index > 0 { divider }
                infinityRow(titleKey: item.rawValue, systemImage: item.icon,
                            isDestructive: item.isDestructive, action: { onCommand(item) })
                    .disabled(!canvasReady && item.requiresCanvas)
            }
        }
        .frame(minWidth: isPad ? 220 : 196)
        .padding(.vertical, isPad ? 6 : 4)
        .background(
            RoundedRectangle(cornerRadius: isPad ? 16 : 14, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: isPad ? 16 : 14, style: .continuous)
                        .stroke(stroke, lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 10, y: 4)
    }

    private var divider: some View {
        Divider()
            .padding(.leading, isPad ? 44 : 40)
    }

    @ViewBuilder
    private func infinityRow(
        titleKey: String,
        systemImage: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: isPad ? 16 : 15, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red.opacity(0.85) : Color.primary.opacity(0.55))
                .frame(width: 24, alignment: .center)
            Text(NSLocalizedString(titleKey, comment: ""))
                .font(.system(size: isPad ? 16 : 15, weight: .medium))
                .foregroundStyle(isDestructive ? Color.primary : Color.primary.opacity(0.88))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isPad ? 16 : 14)
        .padding(.vertical, isPad ? 12 : 10)
        .contentShape(Rectangle())

        Button(role: isDestructive ? .destructive : nil, action: action) { label }
            .buttonStyle(.plain)
    }
}
