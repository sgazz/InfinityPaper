import SwiftUI
import UIKit

struct CanvasFloatingToolbar: View {
    @ObservedObject var broker: CanvasToolbarStateBroker
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    var onMyDrawings: () -> Void
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

    private enum Popover { case color, width, more }
    @State private var activePopover: Popover?

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
        Color(uiColor: broker.state.strokePreviewUIColor)
    }

    /// All toolbar popovers should open downward.
    private var popoverArrow: Edge { .top }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: interItemSpacing) { controlButtons }
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 4) { controlButtons }
                .fixedSize(horizontal: true, vertical: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) { controlButtons }
                    .fixedSize(horizontal: true, vertical: false)
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
        Group {
            colorButton
            widthButton

            CanvasToolbarToolMenu(state: broker.state, isPad: isPad, iconFrame: iconFrame,
                                  onAction: broker.perform)

            commandButton("toolbar.undo", icon: "arrow.uturn.backward", action: onUndo)
                .disabled(!broker.state.undoEnabled)
                .opacity(broker.state.undoEnabled ? 1 : 0.35)
            commandButton("toolbar.redo", icon: "arrow.uturn.forward", action: onRedo)
                .disabled(!broker.state.redoEnabled)
                .opacity(broker.state.redoEnabled ? 1 : 0.35)
            commandButton("toolbar.export", icon: "square.and.arrow.up", action: onExport)
            commandButton(broker.state.paperMovementLocked ? "toolbar.paper_unlock" : "toolbar.paper_lock", icon: broker.state.paperMovementLocked ? "lock.fill" : "lock.open.fill",
                          compact: true, action: onTogglePaperLock)
                .opacity(broker.state.paperMovementLocked ? 1 : 0.72)

        }
        .disabled(!broker.state.canvasReady)

        Button {
            activePopover = .more
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: isPad ? 22 : 20, weight: .medium))
                .frame(width: iconFrame, height: iconFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "toolbar.more")))
        .accessibilityHint(Text(String(localized: "toolbar.infinity_a11y_hint")))
        .padding(.trailing, 2)
        .popover(isPresented: isPresented(.more), attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrow) {
            CanvasToolbarMoreMenu(isPad: isPad, canvasReady: broker.state.canvasReady) { command in
                activePopover = nil
                perform(command)
            }
            .presentationCompactAdaptation(.popover)
        }

        commandButton("toolbar.settings", icon: "gearshape", compact: true, action: onSettings)
            .disabled(!broker.state.canvasReady)
    }

    private var colorButton: some View {
        Button {
            activePopover = .color
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
        .popover(isPresented: isPresented(.color), attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrow) {
            CanvasToolbarPickerPanel(isPad: isPad) {
                CanvasToolbarColorPickerBody(
                    colors: broker.state.palette,
                    selectedIndex: broker.state.selectedColorIndex,
                    isPad: isPad,
                    onPick: { idx in
                        onSelectColor(idx)
                        activePopover = nil
                    }
                )
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var widthButton: some View {
        Button {
            activePopover = .width
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "lineweight")
                    .font(.system(size: isPad ? 17 : 15, weight: .medium))
                Text(broker.state.lineWidthLabel)
                    .font(.system(size: isPad ? 9 : 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: iconFrame, height: iconFrame)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "toolbar.line_width")))
        .popover(isPresented: isPresented(.width), attachmentAnchor: .rect(.bounds), arrowEdge: popoverArrow) {
            CanvasToolbarPickerPanel(isPad: isPad) {
                CanvasToolbarLineWidthPickerBody(
                    presets: TapeCanvasUIView.toolbarWidthPresets,
                    selectedIndex: broker.state.selectedWidthPresetIndex,
                    isPad: isPad,
                    sampleTint: iconTint,
                    onPick: { idx in
                        onSelectLineWidthPreset(idx)
                        activePopover = nil
                    }
                )
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func isPresented(_ popover: Popover) -> Binding<Bool> {
        Binding(get: { activePopover == popover }, set: { shown in
            if shown { activePopover = popover }
            else if activePopover == popover { activePopover = nil }
        })
    }

    private func perform(_ command: CanvasToolbarMoreCommand) {
        switch command {
        case .drawings: onMyDrawings()
        case .clear: onInfinityClearCanvas()
        case .newDrawing: onInfinityNewSpace()
        case .center: onInfinityCenterView()
        case .zoomIn: onInfinityZoomIn()
        case .zoomOut: onInfinityZoomOut()
        case .resetView: onInfinityResetView()
        case .fitContent: onInfinityFitContent()
        case .focus: onInfinityFocusMode()
        }
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
