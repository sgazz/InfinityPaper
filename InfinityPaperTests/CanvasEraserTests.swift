import XCTest
import UIKit
@testable import InfinityPaper

final class CanvasEraserTests: XCTestCase {
    private func line(_ y: CGFloat) -> TapeSessionStroke {
        TapeSessionStroke(points: [CGPoint(x: 0, y: y), CGPoint(x: 100, y: y)], times: [0, 1],
                          color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 2)
    }

    func testFastSweepHitsSegmentBetweenSparseSamples() {
        XCTAssertTrue(CanvasStrokeHitTesting.intersects(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            from: CGPoint(x: 50, y: -30), to: CGPoint(x: 50, y: 30), radius: 1))
        XCTAssertFalse(CanvasStrokeHitTesting.intersects(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            from: CGPoint(x: 50, y: 20), to: CGPoint(x: 60, y: 20), radius: 5))
    }

    func testDotAndCollinearHitTesting() {
        XCTAssertTrue(CanvasStrokeHitTesting.intersects(points: [.zero], from: .zero, to: .zero, radius: 2))
        XCTAssertTrue(CanvasStrokeHitTesting.intersects(points: [.zero, CGPoint(x: 100, y: 0)],
            from: CGPoint(x: 50, y: 0), to: CGPoint(x: 150, y: 0), radius: 1))
        XCTAssertFalse(CanvasStrokeHitTesting.intersects(points: [.zero, CGPoint(x: 10, y: 0)],
            from: CGPoint(x: 50, y: 0), to: CGPoint(x: 150, y: 0), radius: 1))
    }

    func testOneGestureRestoresSeveralStrokesInOriginalOrder() {
        let state = TapeCanvasSessionState()
        let lines = [line(0), line(30), line(60), line(90)]
        lines.forEach { state.commitCompletedStroke($0) }
        state.beginErasing()
        XCTAssertTrue(state.erase(from: CGPoint(x: 50, y: 90), to: CGPoint(x: 50, y: 90), radius: 2))
        XCTAssertTrue(state.erase(from: CGPoint(x: 50, y: 30), to: CGPoint(x: 50, y: 30), radius: 2))
        state.endErasing()
        XCTAssertEqual(state.orderedStrokes.map(\.id), [lines[0].id, lines[2].id])
        XCTAssertTrue(state.undoLastStroke())
        XCTAssertEqual(state.orderedStrokes.map(\.id), lines.map(\.id))
        XCTAssertTrue(state.redoLastStroke())
        XCTAssertEqual(state.orderedStrokes.map(\.id), [lines[0].id, lines[2].id])
        XCTAssertTrue(state.visibleStrokes(in: CGRect(x: 0, y: 25, width: 100, height: 10)).isEmpty)
    }

    func testErasingLoadedDrawingIsUndoableAndPersists() throws {
        let source = TapeCanvasSessionState()
        source.commitCompletedStroke(line(0))
        let state = TapeCanvasSessionState()
        try state.applyStoredSession(source.buildStoredSession(contentOffset: .zero, savedAt: 1))
        XCTAssertFalse(state.canUndo)
        state.erase(from: .zero, to: .zero, radius: 10)
        state.endErasing()
        XCTAssertTrue(state.orderedStrokes.isEmpty)
        XCTAssertTrue(state.hasUnsavedChanges)
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(state.buildStoredSession(contentOffset: .zero, savedAt: 2))
        XCTAssertTrue(restored.orderedStrokes.isEmpty)
        XCTAssertTrue(state.undoLastStroke())
        XCTAssertEqual(state.orderedStrokes.count, 1)
    }

    func testEmptyEraseKeepsRedoAndNewEraseInvalidatesIt() {
        let state = TapeCanvasSessionState()
        state.commitCompletedStroke(line(0))
        state.commitCompletedStroke(line(30))
        state.undoLastStroke()
        state.erase(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 100, y: 100), radius: 1)
        state.endErasing()
        XCTAssertTrue(state.canRedo)
        state.erase(from: .zero, to: .zero, radius: 1)
        state.endErasing()
        XCTAssertFalse(state.canRedo)
    }
    func testEraserFollowsTheVisibleSmoothedCenterline() {
        let state = TapeCanvasSessionState()
        let stroke = TapeSessionStroke(points: [.zero, CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)], times: [0, 1, 2],
                                       color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 2)
        state.commitCompletedStroke(stroke)
        XCTAssertTrue(state.erase(from: CGPoint(x: 50, y: 25), to: CGPoint(x: 50, y: 25), radius: 2))
        state.endErasing()
        XCTAssertTrue(state.orderedStrokes.isEmpty)
    }

}
