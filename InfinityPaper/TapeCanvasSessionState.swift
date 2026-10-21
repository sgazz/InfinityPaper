import UIKit

struct TapeSessionStroke {
    var id = UUID()
    var points: [CGPoint]
    var times: [TimeInterval]
    var color: UIColor
    var lineWidth: CGFloat
    var widthScales: [CGFloat] = []
    var lineStyle: CanvasLineStyle = .solid
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
    private(set) var referenceImage: ReferenceImage?
    private var strokes: [UUID: TapeSessionStroke] = [:]
    private var drawingOrder: [UUID] = []
    private var orderIndex: [UUID: Int] = [:]
    private var boundsByID: [UUID: CGRect] = [:]
    private var columnsByID: [UUID: [Int]] = [:]
    private var columnIndex: [Int: Set<UUID>] = [:]
    private enum Edit {
        case reference(before: ReferenceImage?, after: ReferenceImage?)
        case add([TapeSessionStroke])
        case move(before: [TapeSessionStroke], after: [TapeSessionStroke])
        case erase([(index: Int, stroke: TapeSessionStroke)])
    }
    private var undoHistory: [Edit] = []
    private var redoHistory: [Edit] = []
    private var erasePositions: [UUID: Int]?
    private var erasedStrokes: [(index: Int, stroke: TapeSessionStroke)] = []
    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }
    var orderedStrokes: [TapeSessionStroke] { drawingOrder.compactMap { strokes[$0] } }

    func clear() {
        removeDrawing()
        generation = UUID()
        noteMutationForPersistence()
    }

    private func removeDrawing() {
        referenceImage = nil
        strokes.removeAll()
        drawingOrder.removeAll()
        orderIndex.removeAll()
        boundsByID.removeAll()
        columnsByID.removeAll()
        columnIndex.removeAll()
        undoHistory.removeAll()
        redoHistory.removeAll()
        erasePositions = nil
        erasedStrokes.removeAll()
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

    func visibleStrokes(in viewport: CGRect, including includedIDs: Set<UUID> = []) -> [TapeSessionStroke] {
        var ids = Set<UUID>()
        let first = Int(floor(viewport.minX / Self.segmentWidth))
        let last = Int(floor(viewport.maxX / Self.segmentWidth))
        if last - first < columnIndex.count {
            for column in first...last { ids.formUnion(columnIndex[column] ?? []) }
        } else {
            for (column, strokes) in columnIndex where column >= first && column <= last { ids.formUnion(strokes) }
        }
        ids.formUnion(includedIDs)
        return ids.filter { includedIDs.contains($0) || boundsByID[$0]?.intersects(viewport) == true }
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
        let padding = PencilStrokeWidth.radius(lineWidth: stroke.lineWidth, scales: stroke.widthScales) + 3
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
        var result = rects.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
        if let referenceImage, referenceImage.isVisible, referenceImage.opacity > 0 {
            result = result?.union(referenceImage.rect) ?? referenceImage.rect
        }
        return result
    }

    func worldBoundingRectForExport(currentStroke: TapeSessionStroke?, includeReference: Bool = false) -> CGRect? {
        var rect = boundsByID.values.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
        if let stroke = currentStroke, let padded = paddedBounds(of: stroke) {
            rect = rect?.union(padded) ?? padded
        }
        if includeReference, let referenceImage, referenceImage.isVisible, referenceImage.opacity > 0 {
            rect = rect?.union(referenceImage.rect) ?? referenceImage.rect
        }
        return rect
    }

    func buildStoredSession(contentOffset: CGPoint, zoomScale: CGFloat = 1,
                            currentStroke: TapeSessionStroke? = nil, savedAt: TimeInterval) -> StoredSession {
        let drawing = orderedStrokes + (currentStroke.map { [$0] } ?? [])
        let stored = drawing.map { stroke in
            StoredStroke(points: stroke.points.map { StoredPoint(x: $0.x, y: $0.y) }, times: stroke.times,
                         color: stroke.color.toStoredColor(), lineWidth: stroke.lineWidth,
                         widthScales: stroke.widthScales.isEmpty ? nil : stroke.widthScales, lineStyle: stroke.lineStyle)
        }
        // Version 2 stores a single ordered sequence. The spatial grid is rebuilt, never persisted.
        return StoredSession(segments: [StoredSegment(id: 0, strokes: stored)],
                             contentOffset: StoredPoint(x: contentOffset.x, y: contentOffset.y), savedAt: savedAt,
                             formatVersion: 2, zoomScale: zoomScale, referenceImage: referenceImage)
    }

    func applyStoredSession(_ session: StoredSession) throws {
        try SessionPersistence.validate(session)
        // Legacy files did not store chronology between columns. Preserve order within each column.
        let segments = (session.formatVersion ?? 1) < 2 ? session.segments.sorted { $0.id < $1.id } : session.segments
        let drawing = segments.flatMap { $0.strokes }.map { stroke in
            TapeSessionStroke(points: stroke.points.map { CGPoint(x: $0.x, y: $0.y) }, times: stroke.times ?? [],
                              color: stroke.color.toUIColor(), lineWidth: stroke.lineWidth, widthScales: stroke.widthScales ?? [], lineStyle: stroke.lineStyle ?? .solid)
        }
        removeDrawing()
        for stroke in drawing { insert(stroke) }
        referenceImage = session.referenceImage
        generation = UUID()
        revision &+= 1
        hasUnsavedChanges = false
    }

    private func record(_ edit: Edit) {
        undoHistory.append(edit)
        if undoHistory.count > Self.historyLimit { undoHistory.removeFirst() }
        redoHistory.removeAll()
    }

    private func rebuild(_ drawing: [TapeSessionStroke]) {
        strokes.removeAll(); drawingOrder.removeAll(); orderIndex.removeAll()
        boundsByID.removeAll(); columnsByID.removeAll(); columnIndex.removeAll()
        for stroke in drawing { insert(stroke) }
    }

    func commitCompletedStroke(_ stroke: TapeSessionStroke) {
        guard !stroke.points.isEmpty, strokes[stroke.id] == nil else { return }
        endErasing()
        insert(stroke)
        record(.add([stroke]))
        noteMutationForPersistence()
    }

    func beginErasing() {
        guard erasePositions == nil else { return }
        erasePositions = orderIndex
        erasedStrokes.removeAll()
    }

    @discardableResult
    func erase(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Bool {
        beginErasing()
        let area = CGRect(x: min(start.x, end.x) - radius, y: min(start.y, end.y) - radius,
                          width: abs(end.x - start.x) + 2 * radius, height: abs(end.y - start.y) + 2 * radius)
        let hits = visibleStrokes(in: area).filter {
            CanvasStrokeHitTesting.intersects(points: CanvasStrokeGeometry.smoothedPoints(for: $0.points, passes: 2), from: start, to: end,
                                              radius: radius + PencilStrokeWidth.radius(lineWidth: $0.lineWidth, scales: $0.widthScales))
        }
        guard !hits.isEmpty else { return false }
        for stroke in hits { erasedStrokes.append((erasePositions?[stroke.id] ?? 0, stroke)) }
        let removed = Set(hits.map(\.id))
        rebuild(orderedStrokes.filter { !removed.contains($0.id) })
        noteMutationForPersistence()
        return true
    }

    func endErasing() {
        guard erasePositions != nil else { return }
        if !erasedStrokes.isEmpty { record(.erase(erasedStrokes.sorted { $0.index < $1.index })) }
        erasePositions = nil
        erasedStrokes.removeAll()
    }

    func selectionBounds(for ids: Set<UUID>) -> CGRect? {
        ids.compactMap { boundsByID[$0] }.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
    }

    func selectionCoordinateBounds(for ids: Set<UUID>) -> CGRect? {
        CanvasSelectionGeometry.bounds(of: drawingOrder.filter { ids.contains($0) }.compactMap { strokes[$0] }.flatMap(\.points))
    }

    func strokesIntersectingLasso(_ polygon: [CGPoint]) -> Set<UUID> {
        guard polygon.count >= 3, let bounds = CanvasSelectionGeometry.bounds(of: polygon),
              bounds.width > 0, bounds.height > 0 else { return [] }
        return Set(visibleStrokes(in: bounds).filter {
            CanvasSelectionGeometry.intersects(points: CanvasStrokeGeometry.smoothedPoints(for: $0.points, passes: 2), polygon: polygon)
        }.map(\.id))
    }

    func stroke(at point: CGPoint, radius: CGFloat) -> UUID? {
        visibleStrokes(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            .reversed().first {
                CanvasStrokeHitTesting.intersects(points: CanvasStrokeGeometry.smoothedPoints(for: $0.points, passes: 2),
                    from: point, to: point, radius: radius + PencilStrokeWidth.radius(lineWidth: $0.lineWidth, scales: $0.widthScales))
            }?.id
    }

    @discardableResult
    func moveSelection(_ ids: Set<UUID>, by proposed: CGPoint) -> Bool {
        endErasing()
        guard let bounds = selectionCoordinateBounds(for: ids) else { return false }
        let delta = CanvasSelectionGeometry.clampedTranslation(proposed, bounds: bounds)
        guard abs(delta.x) > 1e-8 || abs(delta.y) > 1e-8 else { return false }
        let before = orderedStrokes.filter { ids.contains($0.id) }
        let after = before.map { translated($0, by: delta) }
        let edit = Edit.move(before: before, after: after)
        record(edit)
        apply(edit, undo: false)
        return true
    }

    @discardableResult
    func duplicateSelection(_ ids: Set<UUID>, offset proposed: CGPoint) -> Set<UUID> {
        endErasing()
        guard let bounds = selectionCoordinateBounds(for: ids) else { return [] }
        let delta = CanvasSelectionGeometry.clampedTranslation(proposed, bounds: bounds)
        let copies = orderedStrokes.filter { ids.contains($0.id) }.map { stroke -> TapeSessionStroke in
            var copy = translated(stroke, by: delta)
            copy.id = UUID()
            return copy
        }
        let edit = Edit.add(copies)
        record(edit)
        apply(edit, undo: false)
        return Set(copies.map(\.id))
    }

    @discardableResult
    func deleteSelection(_ ids: Set<UUID>) -> Bool {
        endErasing()
        let removed = orderedStrokes.enumerated().compactMap { index, stroke in
            ids.contains(stroke.id) ? (index: index, stroke: stroke) : nil
        }
        guard !removed.isEmpty else { return false }
        let edit = Edit.erase(removed)
        record(edit)
        apply(edit, undo: false)
        return true
    }

    private func translated(_ stroke: TapeSessionStroke, by delta: CGPoint) -> TapeSessionStroke {
        var result = stroke
        result.points = stroke.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return result
    }

    func setReferenceImage(_ reference: ReferenceImage?) throws {
        try reference?.validate()
        guard reference != referenceImage else { return }
        let edit = Edit.reference(before: referenceImage, after: reference)
        record(edit)
        apply(edit, undo: false)
    }

    private func apply(_ edit: Edit, undo: Bool) {
        var drawing = orderedStrokes
        switch edit {
        case .reference(let before, let after): referenceImage = undo ? before : after
        case .add(let added):
            if undo {
                let ids = Set(added.map(\.id))
                drawing.removeAll { ids.contains($0.id) }
            } else { drawing.append(contentsOf: added) }
        case .move(let before, let after):
            let replacements = Dictionary(uniqueKeysWithValues: (undo ? before : after).map { ($0.id, $0) })
            drawing = drawing.map { replacements[$0.id] ?? $0 }
        case .erase(let removed):
            if undo {
                for item in removed { drawing.insert(item.stroke, at: min(item.index, drawing.count)) }
            } else {
                let ids = Set(removed.map { $0.stroke.id })
                drawing.removeAll { ids.contains($0.id) }
            }
        }
        rebuild(drawing)
        noteMutationForPersistence()
    }

    @discardableResult
    func undoLastStroke() -> Bool {
        endErasing()
        guard let edit = undoHistory.popLast() else { return false }
        apply(edit, undo: true)
        redoHistory.append(edit)
        return true
    }

    @discardableResult
    func redoLastStroke() -> Bool {
        endErasing()
        guard let edit = redoHistory.popLast() else { return false }
        apply(edit, undo: false)
        undoHistory.append(edit)
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
