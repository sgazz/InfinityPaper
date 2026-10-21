import XCTest
import UIKit
@testable import InfinityPaper

final class CanvasLineStyleTests: XCTestCase {
    func testDashPhaseContinuesAcrossSamples() {
        let source = [
            PreparedRenderStrokeSegment(start: .zero, end: CGPoint(x: 7, y: 0), width: 2),
            PreparedRenderStrokeSegment(start: CGPoint(x: 7, y: 0), end: CGPoint(x: 30, y: 0), width: 3)
        ]
        let dashed = CanvasRenderer.patternedSegments(source, style: .dashed, baseWidth: 2)
        XCTAssertEqual(dashed.map { $0.start.x }, [0, 7, 18])
        XCTAssertEqual(dashed.map { $0.end.x }, [7, 10, 28])
        XCTAssertEqual(dashed.map(\.width), [2, 3, 3])
    }

    func testDottedStrokeHasSeparatedShortMarks() {
        let source = [PreparedRenderStrokeSegment(start: .zero, end: CGPoint(x: 20, y: 0), width: 2)]
        let dots = CanvasRenderer.patternedSegments(source, style: .dotted, baseWidth: 2)
        XCTAssertEqual(dots.count, 3)
        XCTAssertEqual(dots[1].start.x, 8.02, accuracy: 0.0001)
        XCTAssertTrue(dots.allSatisfy { abs($0.end.x - $0.start.x - 0.02) < 0.0001 })
        let solid = CanvasRenderer.patternedSegments(source, style: .solid, baseWidth: 2)
        XCTAssertEqual(solid.count, 1)
        XCTAssertEqual(solid[0].end, source[0].end)
    }

    func testStylesSurviveSaveLoadAndLegacyDefaultsToSolid() throws {
        let state = TapeCanvasSessionState()
        for style in CanvasLineStyle.allCases {
            state.commitCompletedStroke(TapeSessionStroke(points: [.zero, CGPoint(x: 50, y: 10)],
                times: [0, 1], color: .black, lineWidth: 3, lineStyle: style))
        }
        let stored = state.buildStoredSession(contentOffset: .zero, savedAt: 1)
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(SessionPersistence.decode(from: SessionPersistence.encode(stored)))
        XCTAssertEqual(restored.orderedStrokes.map(\.lineStyle), CanvasLineStyle.allCases)
        var legacy = stored
        for i in legacy.segments[0].strokes.indices { legacy.segments[0].strokes[i].lineStyle = nil }
        try restored.applyStoredSession(SessionPersistence.decode(from: SessionPersistence.encode(legacy)))
        XCTAssertTrue(restored.orderedStrokes.allSatisfy { $0.lineStyle == .solid })
    }

    func testPreparedStylesKeepVisibleGapsAndPressureWidths() throws {
        let points = (0..<50).map { CGPoint(x: $0 * 5, y: 0) }
        for style in [CanvasLineStyle.dashed, .dotted] {
            let stroke = RenderStroke(points: points, times: [], color: .black, lineWidth: 3,
                                      widthScales: Array(repeating: 2, count: points.count), lineStyle: style)
            let prepared = try XCTUnwrap(CanvasRenderer.prepareStroke(stroke))
            XCTAssertTrue(prepared.segments.contains { $0.width > 3 })
            XCTAssertTrue(zip(prepared.segments, prepared.segments.dropFirst()).contains { a, b in b.start.x > a.end.x + 1 })
        }
    }
}
