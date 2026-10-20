//
//  CanvasFloatingToolbar.swift
//  InfinityPaper
//
//  SwiftUI capsule toolbar: primary drawing controls with calm paper/graphite styling.
//

import Combine
import SwiftUI
import UIKit

// MARK: - State broker (toolbar ↔ UIKit canvas)

@MainActor
final class CanvasToolbarStateBroker: ObservableObject {
    weak var canvas: TapeCanvasUIView?

    @Published var undoEnabled: Bool = false
    @Published var redoEnabled: Bool = false
    @Published var lineWidthLabel: String = ""
    @Published var selectedColorIndex: Int = 0
    @Published var selectedWidthPresetIndex: Int = 0
    @Published var paperMovementLocked: Bool = false
    /// Matches actual stroke (e.g. white in dark mode for first slot), unlike raw palette swatches.
    @Published var strokePreviewUIColor: UIColor = .darkGray
    private var syncQueued = false

    func attach(_ canvas: TapeCanvasUIView) {
        self.canvas = canvas
        syncFromCanvas()
    }

    /// Schedules a sync so `@Published` updates never run during SwiftUI view updates
    /// (e.g. `UIViewRepresentable.makeUIView` calling `attach` → would warn otherwise).
    func syncFromCanvas() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncQueued = false
            self.applySyncFromCanvas()
        }
    }

    private func applySyncFromCanvas() {
        guard let canvas else {
            if undoEnabled { undoEnabled = false }
            if redoEnabled { redoEnabled = false }
            if !lineWidthLabel.isEmpty { lineWidthLabel = "" }
            if selectedColorIndex != 0 { selectedColorIndex = 0 }
            if selectedWidthPresetIndex != 0 { selectedWidthPresetIndex = 0 }
            if paperMovementLocked { paperMovementLocked = false }
            if strokePreviewUIColor != .darkGray { strokePreviewUIColor = .darkGray }
            return
        }
        let nextUndo = canvas.toolbarUndoEnabled
        if undoEnabled != nextUndo { undoEnabled = nextUndo }
        let nextRedo = canvas.toolbarRedoEnabled
        if redoEnabled != nextRedo { redoEnabled = nextRedo }
        let nextLineWidthLabel = String(format: "%.1f", canvas.toolbarBaseLineWidth)
        if lineWidthLabel != nextLineWidthLabel { lineWidthLabel = nextLineWidthLabel }
        let nextColorIndex = canvas.toolbarSelectedPaletteIndex
        if selectedColorIndex != nextColorIndex { selectedColorIndex = nextColorIndex }
        let nextWidthIndex = canvas.toolbarWidthPresetIndex()
        if selectedWidthPresetIndex != nextWidthIndex { selectedWidthPresetIndex = nextWidthIndex }
        let nextLocked = canvas.toolbarPaperMovementLocked
        if paperMovementLocked != nextLocked { paperMovementLocked = nextLocked }
        let nextPreviewColor = canvas.exposedBaseStrokeColor
        if strokePreviewUIColor != nextPreviewColor { strokePreviewUIColor = nextPreviewColor }
    }

    var paletteUIColors: [UIColor] {
        canvas?.exposedPrimaryPalette ?? []
    }
}

// MARK: - Picker chrome (shared mini-panel look)

private struct ToolbarPickerPanel<Content: View>: View {
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

private struct ToolbarColorPickerBody: View {
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

private struct ToolbarLineWidthPickerBody: View {
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

// MARK: - Infinity brand menu (popover)

private struct InfinityToolbarPopover: View {
    @Environment(\.colorScheme) private var colorScheme
    let isPad: Bool
    let onClearCanvas: () -> Void
    let onNewSpace: () -> Void
    let onCenterView: () -> Void
    let onFocusMode: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onResetView: () -> Void
    let onFitContent: () -> Void

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
            ForEach(Array(menuItems.enumerated()), id: \.offset) { index, item in
                if index > 0 { divider }
                infinityRow(titleKey: item.title, systemImage: item.icon,
                            isDestructive: index == 0, action: item.action)
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

    private var menuItems: [(title: String, icon: String, action: () -> Void)] {
        [
            ("toolbar.infinity_clear", "trash", onClearCanvas),
            ("toolbar.infinity_new_space", "square.dashed", onNewSpace),
            ("toolbar.infinity_center", "scope", onCenterView),
            ("toolbar.infinity_zoom_in", "plus.magnifyingglass", onZoomIn),
            ("toolbar.infinity_zoom_out", "minus.magnifyingglass", onZoomOut),
            ("toolbar.infinity_reset_view", "arrow.counterclockwise", onResetView),
            ("toolbar.infinity_fit_content", "arrow.up.left.and.down.right.magnifyingglass", onFitContent),
            ("toolbar.infinity_focus", "moon.stars", onFocusMode)
        ]
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

// MARK: - Floating toolbar

struct CanvasFloatingToolbar: View {
    @ObservedObject var broker: CanvasToolbarStateBroker
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    var onSelectColor: (Int) -> Void
    var onSelectLineWidthPreset: (Int) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onExport: () -> Void
    var onSettings: () -> Void
    var onTogglePaperLock: () -> Void
    var onInfinityClearCanvas: () -> Void
    var onInfinityNewSpace: () -> Void
    var onInfinityCenterView: () -> Void
    var onInfinityFocusMode: () -> Void
    var onInfinityZoomIn: () -> Void
    var onInfinityZoomOut: () -> Void
    var onInfinityResetView: () -> Void
    var onInfinityFitContent: () -> Void

    @State private var showColorPicker = false
    @State private var showWidthPicker = false
    @State private var showInfinityMenu = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var capsuleHPadding: CGFloat { isPad ? 22 : 14 }
    private var interItemSpacing: CGFloat { isPad ? 14 : 10 }
    private var iconFrame: CGFloat { isPad ? 40 : 34 }

    private var capsuleFill: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(white: 0.14, alpha: 0.92)
            } else {
                UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 0.94)
            }
        })
    }

    private var strokeLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var iconTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.55)
    }

    private var currentSwatchColor: Color {
        Color(uiColor: broker.strokePreviewUIColor)
    }

    /// All toolbar popovers should open downward.
    private var popoverArrow: Edge { .top }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: interItemSpacing) { controlButtons }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: interItemSpacing) { controlButtons }
            }
            .frame(height: iconFrame)
        }
        .foregroundStyle(iconTint)
        .padding(.horizontal, capsuleHPadding)
        .padding(.vertical, isPad ? 11 : 9)
        .background(
            Capsule(style: .continuous)
                .fill(capsuleFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(strokeLine, lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: isPad ? 14 : 10, y: isPad ? 5 : 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var controlButtons: some View {
        Button {
            showWidthPicker = false
            showColorPicker = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: isPad ? 19 : 17, weight: .medium))
                    .frame(width: iconFrame, height: iconFrame)
                Circle()
                    .fill(currentSwatchColor)
                    .frame(width: isPad ? 11 : 9, height: isPad ? 11 : 9)
                    .overlay(Circle().stroke(strokeLine, lineWidth: 0.5))
                    .offset(x: 2, y: 2)
            }
            .frame(width: iconFrame, height: iconFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "toolbar.color")))
        .popover(isPresented: $showColorPicker, attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrow) {
            ToolbarPickerPanel(isPad: isPad) {
                ToolbarColorPickerBody(
                    colors: broker.paletteUIColors,
                    selectedIndex: broker.selectedColorIndex,
                    isPad: isPad,
                    onPick: { idx in
                        onSelectColor(idx)
                        showColorPicker = false
                    }
                )
            }
            .presentationCompactAdaptation(.popover)
        }

        Button {
            showColorPicker = false
            showWidthPicker = true
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "lineweight")
                    .font(.system(size: isPad ? 17 : 15, weight: .medium))
                Text(broker.lineWidthLabel)
                    .font(.system(size: isPad ? 9 : 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: iconFrame, height: iconFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "toolbar.line_width")))
        .popover(isPresented: $showWidthPicker, attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrow) {
            ToolbarPickerPanel(isPad: isPad) {
                ToolbarLineWidthPickerBody(
                    presets: TapeCanvasUIView.toolbarWidthPresets,
                    selectedIndex: broker.selectedWidthPresetIndex,
                    isPad: isPad,
                    sampleTint: iconTint,
                    onPick: { idx in
                        onSelectLineWidthPreset(idx)
                        showWidthPicker = false
                    }
                )
            }
            .presentationCompactAdaptation(.popover)
        }

        commandButton("toolbar.undo", icon: "arrow.uturn.backward", action: onUndo)
            .disabled(!broker.undoEnabled)
            .opacity(broker.undoEnabled ? 1 : 0.35)
        commandButton("toolbar.redo", icon: "arrow.uturn.forward", action: onRedo)
            .disabled(!broker.redoEnabled)
            .opacity(broker.redoEnabled ? 1 : 0.35)
        commandButton("toolbar.export", icon: "square.and.arrow.up", action: onExport)
        commandButton(broker.paperMovementLocked ? "toolbar.paper_unlock" : "toolbar.paper_lock", icon: broker.paperMovementLocked ? "lock.fill" : "lock.open.fill",
                      compact: true, action: onTogglePaperLock)
            .opacity(broker.paperMovementLocked ? 1 : 0.72)

        Button {
            showColorPicker = false
            showWidthPicker = false
            showInfinityMenu = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: isPad ? 22 : 20, weight: .medium))
                .frame(width: iconFrame, height: iconFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "toolbar.more")))
        .accessibilityHint(Text(String(localized: "toolbar.infinity_a11y_hint")))
        .padding(.trailing, 2)
        .popover(isPresented: $showInfinityMenu, attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrow) {
            InfinityToolbarPopover(
                isPad: isPad,
                onClearCanvas: {
                    showInfinityMenu = false
                    onInfinityClearCanvas()
                },
                onNewSpace: {
                    showInfinityMenu = false
                    onInfinityNewSpace()
                },
                onCenterView: {
                    showInfinityMenu = false
                    onInfinityCenterView()
                },
                onFocusMode: {
                    showInfinityMenu = false
                    onInfinityFocusMode()
                },
                onZoomIn: {
                    showInfinityMenu = false
                    onInfinityZoomIn()
                },
                onZoomOut: {
                    showInfinityMenu = false
                    onInfinityZoomOut()
                },
                onResetView: {
                    showInfinityMenu = false
                    onInfinityResetView()
                },
                onFitContent: {
                    showInfinityMenu = false
                    onInfinityFitContent()
                }
            )
            .presentationCompactAdaptation(.popover)
        }

        commandButton("toolbar.settings", icon: "gearshape", compact: true, action: onSettings)
    }

    private func commandButton(_ titleKey: String, icon: String, compact: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: (isPad ? 19 : 17) - (compact ? 1 : 0), weight: .medium))
                .frame(width: iconFrame, height: iconFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: String.LocalizationValue(titleKey))))
    }
}
