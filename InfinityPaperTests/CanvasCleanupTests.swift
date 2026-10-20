import XCTest
import UIKit
@testable import InfinityPaper

final class CanvasCleanupTests: XCTestCase {
    func testViewportTransformMatchesZoomedScreenCoordinates() {
        let offset = CGPoint(x: 120, y: -40)
        for zoom: CGFloat in [0.5, 1, 2.5] {
            let transform = CanvasGeometry.viewportTransform(offset: offset, zoom: zoom)
            XCTAssertEqual(offset.applying(transform), .zero)
            let point = CGPoint(x: 200, y: 20).applying(transform)
            XCTAssertEqual(point.x, 80 * zoom, accuracy: 0.0001)
            XCTAssertEqual(point.y, 60 * zoom, accuracy: 0.0001)
        }
    }

    func testLargePNGIsCappedEvenWhenLogicalSizeExceedsPixelLimit() {
        for size in [CGSize(width: 4000, height: 2000), CGSize(width: 20000, height: 1000)] {
            let scale = CanvasGeometry.exportScale(size: size, requested: 4)
            XCTAssertLessThanOrEqual(max(size.width, size.height) * scale, 8192)
            XCTAssertGreaterThan(scale, 0)
        }
        XCTAssertEqual(CanvasGeometry.exportScale(size: CGSize(width: 100, height: 100), requested: 2), 2)
    }

    func testFirstBrushColorAdaptsToAppearanceAndInvalidIndicesAreClamped() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(CanvasBrush.color(at: 0, traits: dark), .white)
        XCTAssertEqual(CanvasBrush.color(at: 0, traits: light), CanvasBrush.palette[0])
        XCTAssertEqual(CanvasBrush.color(at: -1, traits: light), CanvasBrush.palette[0])
        XCTAssertEqual(CanvasBrush.color(at: Int.max, traits: light), CanvasBrush.palette.last!)
    }
}
