import Foundation
import Combine
import UIKit

@MainActor
struct CanvasToolbarState: Equatable {
    var canvasReady = false
    var selectedTool = CanvasTool.pen
    var selectedStrokeCount = 0
    var undoEnabled = false
    var redoEnabled = false
    var lineWidthLabel = ""
    var selectedColorIndex = 0
    var selectedWidthPresetIndex = 0
    var lineStyle: CanvasLineStyle = .solid
    var paperMovementLocked = false
    var strokePreviewUIColor = UIColor.darkGray
    var palette: [UIColor] = []
}

@MainActor
protocol CanvasToolbarStateProviding: AnyObject {
    var toolbarState: CanvasToolbarState { get }
}

/// Publishes one consistent toolbar snapshot, at most once per queued synchronization.
@MainActor
final class CanvasToolbarStateBroker: ObservableObject {
    @Published private(set) var state = CanvasToolbarState()
    private weak var source: (any CanvasToolbarStateProviding)?
    var canvas: TapeCanvasUIView? { source as? TapeCanvasUIView }
    private var syncQueued = false

    func attach(_ source: any CanvasToolbarStateProviding) {
        self.source = source
        syncFromCanvas()
    }

    /// Defer publication to avoid changing SwiftUI state during UIViewRepresentable updates.
    func syncFromCanvas() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncQueued = false
            let next = self.source?.toolbarState ?? CanvasToolbarState()
            if self.state != next { self.state = next }
        }
    }

    func perform(_ action: CanvasToolbarToolAction) {
        switch action {
        case .selectTool(let tool): canvas?.toolbarSetTool(tool)
        case .duplicate: canvas?.toolbarDuplicateSelection()
        case .delete: canvas?.toolbarDeleteSelection()
        case .deselect: canvas?.toolbarDeselect()
        }
    }
}

extension TapeCanvasUIView: CanvasToolbarStateProviding {
    var toolbarState: CanvasToolbarState {
        CanvasToolbarState(canvasReady: documentReady, selectedTool: selectedTool, selectedStrokeCount: selectedStrokeCount,
            undoEnabled: toolbarUndoEnabled, redoEnabled: toolbarRedoEnabled,
            lineWidthLabel: String(format: "%.1f", toolbarBaseLineWidth), selectedColorIndex: toolbarSelectedPaletteIndex,
            selectedWidthPresetIndex: toolbarWidthPresetIndex(), lineStyle: lineStyle, paperMovementLocked: toolbarPaperMovementLocked,
            strokePreviewUIColor: exposedBaseStrokeColor, palette: exposedPrimaryPalette)
    }
}
