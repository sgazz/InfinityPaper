import SwiftUI

enum CanvasToolbarToolAction {
    case selectTool(CanvasTool), duplicate, delete, deselect
}

struct CanvasToolbarToolMenu: View {
    let state: CanvasToolbarState
    let isPad: Bool
    let iconFrame: CGFloat
    let onAction: (CanvasToolbarToolAction) -> Void

    var body: some View {
        Menu {
            Section("Drawing tool") {
                toolButton("Pen", icon: "pencil.tip", tool: .pen)
                toolButton("Whole-stroke eraser", icon: "eraser", tool: .eraser)
                toolButton("Lasso selection", icon: "lasso", tool: .lasso)
            }
            if state.selectedTool == .lasso {
                Section("Selected strokes: \(state.selectedStrokeCount)") {
                    Button("Duplicate selection", systemImage: "plus.square.on.square") { onAction(.duplicate) }
                    Button("Delete selection", systemImage: "trash", role: .destructive) { onAction(.delete) }
                    Button("Deselect", systemImage: "xmark.circle") { onAction(.deselect) }
                }
                .disabled(state.selectedStrokeCount == 0)
            }
        } label: {
            Image(systemName: state.selectedTool == .lasso ? "lasso" : state.selectedTool == .eraser ? "eraser.fill" : "pencil.tip")
                .font(.system(size: isPad ? 19 : 17, weight: .medium))
                .frame(width: iconFrame, height: iconFrame)
                .background(state.selectedTool != .pen ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
        }
        .accessibilityLabel("Drawing tool and selection actions")
        .accessibilityValue(state.selectedTool.rawValue)
        .accessibilityHint("Choose pen, eraser or lasso. Selection actions appear in this menu.")
    }

    private func toolButton(_ title: String, icon: String, tool: CanvasTool) -> some View {
        Button { onAction(.selectTool(tool)) } label: {
            Label(title, systemImage: state.selectedTool == tool ? "checkmark" : icon)
        }
    }

}
