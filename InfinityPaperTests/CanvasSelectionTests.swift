import XCTest
import UIKit
@testable import InfinityPaper

final class CanvasSelectionTests: XCTestCase {
    private func line(_ y: CGFloat, x: CGFloat = 0) -> TapeSessionStroke {
        TapeSessionStroke(points: [CGPoint(x: x, y: y), CGPoint(x: x + 100, y: y)], times: [0, 1],
                          color: UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), lineWidth: 2)
    }

    private func snapshot(_ state: TapeCanvasSessionState) -> StoredSession {
        state.buildStoredSession(contentOffset: .zero, savedAt: 1)
    }

    func testLassoSelectsCrossingStrokeAndDotButNotUnrelatedStroke() {
        let state = TapeCanvasSessionState()
        let crossing = line(50), outside = line(100)
        let dot = TapeSessionStroke(points: [CGPoint(x: 50, y: 40)], times: [0],
                                   color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 2)
        [crossing, outside, dot].forEach { state.commitCompletedStroke($0) }
        let polygon = [CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 30), CGPoint(x: 60, y: 60), CGPoint(x: 40, y: 60)]
        XCTAssertEqual(state.strokesIntersectingLasso(polygon), Set([crossing.id, dot.id]))
        XCTAssertTrue(CanvasSelectionGeometry.contains(CGPoint(x: 40, y: 50), polygon: polygon))
    }

    func testConcaveLassoDoesNotSelectItsEmptyCorner() {
        let polygon = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 3),
                       CGPoint(x: 3, y: 3), CGPoint(x: 3, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertTrue(CanvasSelectionGeometry.contains(CGPoint(x: 1, y: 8), polygon: polygon))
        XCTAssertFalse(CanvasSelectionGeometry.contains(CGPoint(x: 8, y: 8), polygon: polygon))
    }

    func testGroupMoveKeepsOrderAndUpdatesSpatialIndexWithOneUndo() throws {
        let state = TapeCanvasSessionState()
        let lines = [line(0), line(30), line(60)]
        lines.forEach { state.commitCompletedStroke($0) }
        XCTAssertTrue(state.moveSelection(Set([lines[0].id, lines[2].id]), by: CGPoint(x: 2000, y: 10)))
        XCTAssertEqual(state.orderedStrokes.map(\.id), lines.map(\.id))
        XCTAssertEqual(state.orderedStrokes.map { $0.points[0].x }, [2000, 0, 2000])
        XCTAssertEqual(state.orderedStrokes[0].times, [0, 1])
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: 1900, y: -20, width: 300, height: 200)).map(\.id), [lines[0].id, lines[2].id])
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: -10, y: -20, width: 200, height: 200)).map(\.id), [lines[1].id])
        XCTAssertTrue(state.undoLastStroke())
        XCTAssertEqual(state.orderedStrokes.map { $0.points[0].x }, [0, 0, 0])
        XCTAssertTrue(state.redoLastStroke())
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(SessionPersistence.decode(from: SessionPersistence.encode(snapshot(state))))
        XCTAssertEqual(restored.orderedStrokes.map { $0.points[0].x }, [2000, 0, 2000])
    }

    func testDuplicateIsOneUndoWithNewIDsAndIndependentPoints() {
        let state = TapeCanvasSessionState()
        let lines = [line(0), line(30)]
        lines.forEach { state.commitCompletedStroke($0) }
        let copies = state.duplicateSelection(Set(lines.map(\.id)), offset: CGPoint(x: 20, y: 40))
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.isDisjoint(with: Set(lines.map(\.id))))
        XCTAssertEqual(state.orderedStrokes.map { $0.points[0].y }, [0, 30, 40, 70])
        XCTAssertTrue(state.undoLastStroke())
        XCTAssertEqual(state.orderedStrokes.map(\.id), lines.map(\.id))
        XCTAssertTrue(state.redoLastStroke())
        XCTAssertEqual(Set(state.orderedStrokes.suffix(2).map(\.id)), copies)
        state.moveSelection(copies, by: CGPoint(x: 100, y: 0))
        XCTAssertEqual(state.orderedStrokes.prefix(2).map { $0.points[0].x }, [0, 0])
    }

    func testDeleteSelectionRestoresOriginalLayerOrder() {
        let state = TapeCanvasSessionState()
        let lines = [line(0), line(30), line(60), line(90)]
        lines.forEach { state.commitCompletedStroke($0) }
        XCTAssertTrue(state.deleteSelection(Set([lines[0].id, lines[2].id])))
        XCTAssertEqual(state.orderedStrokes.map(\.id), [lines[1].id, lines[3].id])
        XCTAssertTrue(state.undoLastStroke())
        XCTAssertEqual(state.orderedStrokes.map(\.id), lines.map(\.id))
        XCTAssertTrue(state.redoLastStroke())
        XCTAssertEqual(state.orderedStrokes.map(\.id), [lines[1].id, lines[3].id])
    }

    func testGroupMoveClampsTogetherAndKeepsSessionValid() throws {
        let state = TapeCanvasSessionState()
        let a = line(0, x: 9_999_890), b = line(30, x: 9_999_800)
        [a, b].forEach { state.commitCompletedStroke($0) }
        XCTAssertTrue(state.moveSelection(Set([a.id, b.id]), by: CGPoint(x: 1000, y: 0)))
        XCTAssertEqual(state.orderedStrokes[0].points.last?.x, CanvasGeometry.coordinateLimit)
        XCTAssertEqual(state.orderedStrokes[1].points.first?.x, 9_999_810)
        try SessionPersistence.validate(snapshot(state))
        state.undoLastStroke()
        XCTAssertEqual(state.orderedStrokes[0].points.first?.x, 9_999_890)
    }

    func testInvalidOrZeroMoveDoesNotDirtyOrAddHistory() throws {
        let source = TapeCanvasSessionState()
        source.commitCompletedStroke(line(0))
        let state = TapeCanvasSessionState()
        try state.applyStoredSession(snapshot(source))
        let ids = Set(state.orderedStrokes.map(\.id))
        XCTAssertFalse(state.moveSelection(ids, by: .zero))
        XCTAssertFalse(state.moveSelection(ids, by: CGPoint(x: CGFloat.infinity, y: 0)))
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertFalse(state.canUndo)
    }

    func testPreviewCancelAndCommitDoNotAccumulateMovementOrUndoSteps() throws {
        let source = TapeCanvasSessionState()
        source.commitCompletedStroke(line(0))
        let state = TapeCanvasSessionState()
        try state.applyStoredSession(snapshot(source))
        let selection = CanvasSelectionController(state: state)
        selection.setEnabled(true)
        selection.begin(at: CGPoint(x: 50, y: 0), zoom: 1)
        selection.finishGesture() // Tap selects the stroke.
        XCTAssertEqual(selection.selectedIDs.count, 1)
        XCTAssertFalse(state.hasUnsavedChanges)
        selection.begin(at: CGPoint(x: 50, y: 0), zoom: 1)
        selection.move(to: CGPoint(x: 70, y: 10))
        selection.move(to: CGPoint(x: 90, y: 20))
        XCTAssertEqual(selection.translation, CGPoint(x: 40, y: 20))
        XCTAssertEqual(state.orderedStrokes[0].points[0], .zero)
        selection.finishGesture(cancelled: true)
        XCTAssertFalse(state.hasUnsavedChanges)
        selection.begin(at: CGPoint(x: 50, y: 0), zoom: 1)
        selection.move(to: CGPoint(x: 90, y: 20))
        selection.finishGesture()
        XCTAssertEqual(state.orderedStrokes[0].points[0], CGPoint(x: 40, y: 20))
        XCTAssertTrue(state.undoLastStroke())
        XCTAssertEqual(state.orderedStrokes[0].points[0], .zero)
        XCTAssertFalse(state.canUndo)
    }

    func testMovingSelectionIsRenderedEvenWhenOriginalBoundsAreOutsideViewport() {
        let state = TapeCanvasSessionState()
        let a = line(0, x: 2000), b = line(30)
        [a, b].forEach { state.commitCompletedStroke($0) }
        let visible = state.visibleStrokes(in: CGRect(x: -10, y: -10, width: 200, height: 100), including: [a.id])
        XCTAssertEqual(visible.map(\.id), [a.id, b.id])
    }

    func testNewEditAfterUndoClearsRedoAndDeletionUsesCurrentCoordinates() {
        let state = TapeCanvasSessionState()
        let a = line(0)
        state.commitCompletedStroke(a)
        state.moveSelection([a.id], by: CGPoint(x: 500, y: 0))
        state.undoLastStroke()
        XCTAssertTrue(state.canRedo)
        state.duplicateSelection([a.id], offset: CGPoint(x: 20, y: 20))
        XCTAssertFalse(state.canRedo)
        state.deleteSelection([a.id])
        XCTAssertEqual(state.orderedStrokes.count, 1)
        state.undoLastStroke()
        XCTAssertEqual(state.orderedStrokes[0].id, a.id)
        XCTAssertEqual(state.orderedStrokes[0].points[0], .zero)
    }
}
