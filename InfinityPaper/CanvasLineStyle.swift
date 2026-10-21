import Foundation

nonisolated enum CanvasLineStyle: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted

    var title: String { NSLocalizedString("line_style." + rawValue, comment: "Stroke style") }

    func dashLengths(width: CGFloat) -> [CGFloat] {
        let unit = max(1, width)
        switch self {
        case .solid: return []
        case .dashed: return [5 * unit, 4 * unit]
        case .dotted: return [0.01 * unit, 4 * unit]
        }
    }
}
