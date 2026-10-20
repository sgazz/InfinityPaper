import XCTest
import UIKit
@testable import InfinityPaper

final class PencilRendererTests: XCTestCase {
    func testDotUsesItsCapturedPressureWidth() throws {
        let stroke = RenderStroke(points: [.zero], times: [0], color: .black, lineWidth: 8, widthScales: [2])
        let prepared = try XCTUnwrap(CanvasRenderer.prepareStroke(stroke))
        XCTAssertEqual(prepared.segments[0].width, 16)
    }

    func testPressureProfileChangesRenderedWidthButNotCoordinates() throws {
        let points = (0..<40).map { CGPoint(x: $0 * 10, y: 0) }
        let times = (0..<40).map { Double($0) * 0.1 }
        let thin = RenderStroke(points: points, times: times, color: .black, lineWidth: 8, widthScales: Array(repeating: 0.4, count: 40))
        let thick = RenderStroke(points: points, times: times, color: .black, lineWidth: 8, widthScales: Array(repeating: 2, count: 40))
        let a = try XCTUnwrap(CanvasRenderer.prepareStroke(thin))
        let b = try XCTUnwrap(CanvasRenderer.prepareStroke(thick))
        XCTAssertGreaterThan(b.segments[5].width, a.segments[5].width)
        XCTAssertEqual(a.segments[5].start, b.segments[5].start)
        XCTAssertEqual(a.segments[5].end, b.segments[5].end)
    }
}
