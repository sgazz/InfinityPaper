import Foundation

nonisolated enum PaperPattern: String, CaseIterable, Codable, Sendable {
    case plain, lines, grid, dots
    var title: String {
        switch self {
        case .plain: return "Plain"
        case .lines: return "Lines"
        case .grid: return "Grid"
        case .dots: return "Dots"
        }
    }
}

nonisolated enum PaperPatternLayout {
    static let defaultSpacing: CGFloat = 32
    static let spacingRange: ClosedRange<CGFloat> = 16...80

    /// Thin out guides when fitting a huge drawing, keeping rendering bounded.
    static func visibleSpacing(_ spacing: CGFloat, zoom: CGFloat, extent: CGFloat = 0) -> CGFloat {
        spacing * max(1, ceil(8 / (spacing * max(CanvasGeometry.minimumZoom, zoom))), ceil(extent / (spacing * 256)))
    }
}
