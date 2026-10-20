import XCTest
import CoreGraphics
@testable import InfinityPaper

final class CanvasViewportTests: XCTestCase {
    func testZoomKeepsTheFocalWorldPointFixed() {
        var viewport = CanvasViewport(offset: CGPoint(x: 100, y: -50), zoom: 0.75)
        let focal = CGPoint(x: 180, y: 260)
        let before = viewport.worldPoint(focal)
        XCTAssertTrue(viewport.zoom(by: 1.5, at: focal))
        let after = viewport.worldPoint(focal)
        XCTAssertEqual(before.x, after.x, accuracy: 0.000001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.000001)
    }

    func testPanUsesWorldCoordinatesAndClampsAtTheSameLimits() {
        var viewport = CanvasViewport(zoom: 2)
        viewport.pan(by: CGPoint(x: 200, y: -100))
        XCTAssertEqual(viewport.offset, CGPoint(x: -100, y: 50))
        viewport.pan(by: CGPoint(x: 100_000_000, y: -100_000_000))
        XCTAssertEqual(viewport.offset, CGPoint(x: -10_000_000, y: 10_000_000))
    }

    func testFitCanBeZoomedInEvenAtVerySmallScale() {
        var viewport = CanvasViewport()
        let drawing = CGRect(x: 0, y: 0, width: 2_000_000, height: 1_000_000)
        viewport.fit(drawing, in: CGSize(width: 400, height: 800))
        let fittedScale = viewport.zoom
        XCTAssertLessThan(fittedScale, 0.001)
        XCTAssertTrue(viewport.zoom(by: 1.2, at: CGPoint(x: 200, y: 400)))
        XCTAssertEqual(viewport.zoom, fittedScale * 1.2, accuracy: 0.000000001)
    }

    func testWorldRectContainsFittedDrawing() {
        var viewport = CanvasViewport()
        let drawing = CGRect(x: -1500, y: -400, width: 2000, height: 800)
        let size = CGSize(width: 400, height: 800)
        viewport.fit(drawing, in: size)
        XCTAssertTrue(viewport.worldRect(for: size).contains(drawing))
    }
}
