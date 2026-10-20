import UIKit

struct TapeSessionStroke {
    var id = UUID()
    var points: [CGPoint]
    var times: [TimeInterval]
    var color: UIColor
    var lineWidth: CGFloat
}

/// In-memory identity of a snapshot. Replaced on clear/load, never persisted.
struct SessionRevision: Equatable {
    let generation: UUID
    let value: UInt64
}

/// A stroke is stored once, in drawing order. The fixed world-space grid only holds IDs.
final class TapeCanvasSessionState {
    static let segmentWidth: CGFloat = 1024
    static let historyLimit = 256
    private var generation = UUID()
    private var revision: UInt64 = 0
    private(set) var hasUnsavedChanges = false
    var persistenceRevision: SessionRevision { SessionRevision(generation: generation, value: revision) }
    private var strokes: [UUID: TapeSessionStroke] = [:]
    private var drawingOrder: [UUID] = []
    private var orderIndex: [UUID: Int] = [:]
    private var boundsByID: [UUID: CGRect] = [:]
    private var columnsByID: [UUID: [Int]] = [:]
    private var columnIndex: [Int: Set<UUID>] = [:]
    private var undoIDs: [UUID] = []
    private var redoStrokes: [TapeSessionStroke] = []
    var canUndo: Bool { !undoIDs.isEmpty }
    var canRedo: Bool { !redoStrokes.isEmpty }
    var orderedStrokes: [TapeSessionStroke] { drawingOrder.compactMap { strokes[$0] } }

    func clear() {
        removeDrawing()
        generation = UUID()
        noteMutationForPersistence()
    }

    private func removeDrawing() {
        strokes.removeAll()
        drawingOrder.removeAll()
        orderIndex.removeAll()
        boundsByID.removeAll()
        columnsByID.removeAll()
        columnIndex.removeAll()
        undoIDs.removeAll()
        redoStrokes.removeAll()
    }

    /// Also tracks active-stroke samples, so an in-flight snapshot cannot acknowledge newer samples.
    func noteMutationForPersistence() {
        revision &+= 1
        hasUnsavedChanges = true
    }

    func acknowledgePersistenceSave(succeededWithRevision snapshot: SessionRevision) {
        guard snapshot == persistenceRevision else { return }
        hasUnsavedChanges = false
    }

    func visibleStrokes(in viewport: CGRect) -> [TapeSessionStroke] {
        var ids = Set<UUID>()
        let first = Int(floor(viewport.minX / Self.segmentWidth))
        let last = Int(floor(viewport.maxX / Self.segmentWidth))
        if last - first < columnIndex.count {
            for column in first...last { ids.formUnion(columnIndex[column] ?? []) }
        } else {
            for (column, strokes) in columnIndex where column >= first && column <= last { ids.formUnion(strokes) }
        }
        return ids.filter { boundsByID[$0]?.intersects(viewport) == true }
            .sorted { (orderIndex[$0] ?? 0) < (orderIndex[$1] ?? 0) }
            .compactMap { strokes[$0] }
    }

    private func columns(intersecting rect: CGRect) -> [Int] {
        let first = Int(floor(rect.minX / Self.segmentWidth))
        let last = Int(floor(rect.maxX / Self.segmentWidth))
        return Array(first...last)
    }

    private func rawBounds(of stroke: TapeSessionStroke) -> CGRect? {
        guard let first = stroke.points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in stroke.points.dropFirst() {
            minX = min(minX, point.x); minY = min(minY, point.y)
            maxX = max(maxX, point.x); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func paddedBounds(of stroke: TapeSessionStroke) -> CGRect? {
        let padding = stroke.lineWidth * 0.75 + 3
        return rawBounds(of: stroke)?.insetBy(dx: -padding, dy: -padding)
    }

    private func insert(_ stroke: TapeSessionStroke) {
        guard strokes[stroke.id] == nil, let rect = paddedBounds(of: stroke) else { return }
        orderIndex[stroke.id] = drawingOrder.count
        drawingOrder.append(stroke.id)
        strokes[stroke.id] = stroke
        boundsByID[stroke.id] = rect
        let columns = columns(intersecting: rect)
        columnsByID[stroke.id] = columns
        for column in columns { columnIndex[column, default: []].insert(stroke.id) }
    }

    func rawWorldBoundingRect(currentStroke: TapeSessionStroke?) -> CGRect? {
        let rects = orderedStrokes.compactMap { rawBounds(of: $0) }
            + (currentStroke.flatMap { rawBounds(of: $0) }.map { [$0] } ?? [])
        return rects.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
    }

    func worldBoundingRectForExport(currentStroke: TapeSessionStroke?) -> CGRect? {
        var rect = boundsByID.values.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
        if let stroke = currentStroke, let padded = paddedBounds(of: stroke) {
            rect = rect?.union(padded) ?? padded
        }
        return rect
    }

    func buildStoredSession(contentOffset: CGPoint, zoomScale: CGFloat = 1,
                            currentStroke: TapeSessionStroke? = nil, savedAt: TimeInterval) -> StoredSession {
        let drawing = orderedStrokes + (currentStroke.map { [$0] } ?? [])
        let stored = drawing.map { stroke in
            StoredStroke(points: stroke.points.map { StoredPoint(x: $0.x, y: $0.y) }, times: stroke.times,
                         color: stroke.color.toStoredColor(), lineWidth: stroke.lineWidth)
        }
        // Version 2 stores a single ordered sequence. The spatial grid is rebuilt, never persisted.
        return StoredSession(segments: [StoredSegment(id: 0, strokes: stored)],
                             contentOffset: StoredPoint(x: contentOffset.x, y: contentOffset.y), savedAt: savedAt,
                             formatVersion: 2, zoomScale: zoomScale)
    }

    func applyStoredSession(_ session: StoredSession) throws {
        try SessionPersistence.validate(session)
        // Legacy files did not store chronology between columns. Preserve order within each column.
        let segments = (session.formatVersion ?? 1) < 2 ? session.segments.sorted { $0.id < $1.id } : session.segments
        let drawing = segments.flatMap { $0.strokes }.map { stroke in
            TapeSessionStroke(points: stroke.points.map { CGPoint(x: $0.x, y: $0.y) }, times: stroke.times ?? [],
                              color: stroke.color.toUIColor(), lineWidth: stroke.lineWidth)
        }
        removeDrawing()
        for stroke in drawing { insert(stroke) }
        generation = UUID()
        revision &+= 1
        hasUnsavedChanges = false
    }

    func commitCompletedStroke(_ stroke: TapeSessionStroke) {
        guard !stroke.points.isEmpty, strokes[stroke.id] == nil else { return }
        insert(stroke)
        undoIDs.append(stroke.id)
        if undoIDs.count > Self.historyLimit { undoIDs.removeFirst() }
        redoStrokes.removeAll()
        noteMutationForPersistence()
    }

    @discardableResult
    func undoLastStroke() -> Bool {
        guard let id = undoIDs.popLast(), let stroke = strokes.removeValue(forKey: id) else { return false }
        drawingOrder.removeLast()
        orderIndex.removeValue(forKey: id)
        boundsByID.removeValue(forKey: id)
        for column in columnsByID.removeValue(forKey: id) ?? [] {
            columnIndex[column]?.remove(id)
            if columnIndex[column]?.isEmpty == true { columnIndex.removeValue(forKey: column) }
        }
        redoStrokes.append(stroke)
        noteMutationForPersistence()
        return true
    }

    @discardableResult
    func redoLastStroke() -> Bool {
        guard let stroke = redoStrokes.popLast() else { return false }
        insert(stroke)
        undoIDs.append(stroke.id)
        noteMutationForPersistence()
        return true
    }
}

extension UIColor {
    func toStoredColor() -> StoredColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return StoredColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
extension StoredColor {
    func toUIColor() -> UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}
