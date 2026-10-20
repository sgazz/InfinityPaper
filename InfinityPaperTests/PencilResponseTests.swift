import XCTest
import UIKit
@testable import InfinityPaper

final class PencilResponseTests: XCTestCase {
    private func stroke() -> TapeSessionStroke {
        TapeSessionStroke(points: [.zero, CGPoint(x: 100, y: 0)], times: [0, 1],
            color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 8, widthScales: [0.4, 2])
    }

    func testPressureIsMonotonicAndSensitivityRespondsToLighterForce() {
        let light = PencilResponse(pressureEnabled: true, tiltEnabled: false, sensitivity: 0)
        let sensitive = PencilResponse(pressureEnabled: true, tiltEnabled: false, sensitivity: 1)
        XCTAssertLessThan(light.scale(force: 0.1, maximumForce: 1, altitude: .pi / 2), light.scale(force: 0.8, maximumForce: 1, altitude: .pi / 2))
        XCTAssertGreaterThan(sensitive.scale(force: 0.3, maximumForce: 1, altitude: .pi / 2), light.scale(force: 0.3, maximumForce: 1, altitude: .pi / 2))
    }

    func testDisabledDynamicsAndUnavailableForceKeepNormalWidth() {
        let disabled = PencilResponse(pressureEnabled: false, tiltEnabled: false, sensitivity: 1)
        XCTAssertEqual(disabled.scale(force: 1, maximumForce: 1, altitude: 0), 1)
        let pressure = PencilResponse(pressureEnabled: true, tiltEnabled: false, sensitivity: 0.5)
        XCTAssertEqual(pressure.scale(force: 0, maximumForce: 0, altitude: .pi / 2), 1)
        XCTAssertEqual(pressure.scale(force: .nan, maximumForce: 1, altitude: .pi / 2), 1)
        XCTAssertEqual(pressure.scale(force: 1, maximumForce: .infinity, altitude: .pi / 2), 1)
        XCTAssertEqual(pressure.scale(force: 1, maximumForce: 1, altitude: .pi / 2), 1)
        XCTAssertEqual(pressure.scale(force: 1, maximumForce: 4, altitude: .pi / 2), 1)
    }

    func testTiltWidensAndExtremeInputStaysBounded() {
        let tilt = PencilResponse(pressureEnabled: false, tiltEnabled: true, sensitivity: 0.5)
        XCTAssertEqual(tilt.scale(force: 0, maximumForce: 0, altitude: .pi / 2), 1)
        XCTAssertGreaterThan(tilt.scale(force: 0, maximumForce: 0, altitude: 0.1), 1)
        XCTAssertEqual(tilt.scale(force: 0, maximumForce: 0, altitude: .nan), 1)
        let both = PencilResponse(pressureEnabled: true, tiltEnabled: true, sensitivity: .nan)
        XCTAssertEqual(both.scale(force: 100, maximumForce: 10, altitude: 0), 2)
        XCTAssertGreaterThanOrEqual(both.scale(force: -1, maximumForce: 1, altitude: 0), PencilStrokeWidth.scaleRange.lowerBound)
    }

    func testPencilOnlyInputDoesNotDisableFingerDrawingOnPhone() {
        XCTAssertTrue(CanvasInputPolicy.pencilOnly(requested: true, supportsPencil: true))
        XCTAssertFalse(CanvasInputPolicy.pencilOnly(requested: true, supportsPencil: false))
        XCTAssertFalse(CanvasInputPolicy.acceptsDrawing(isPencil: false, pencilOnly: true))
        XCTAssertTrue(CanvasInputPolicy.acceptsDrawing(isPencil: true, pencilOnly: true))
        XCTAssertTrue(CanvasInputPolicy.acceptsDrawing(isPencil: false, pencilOnly: false))
        XCTAssertEqual(CanvasInputPolicy.panTouchCount(pencilOnly: true), 1)
        XCTAssertEqual(CanvasInputPolicy.panTouchCount(pencilOnly: false), 2)
    }

    func testWidthProfileSurvivesSaveMoveDuplicateAndUndo() throws {
        let state = TapeCanvasSessionState()
        let original = stroke()
        state.commitCompletedStroke(original)
        let stored = state.buildStoredSession(contentOffset: .zero, savedAt: 1)
        let decoded = try SessionPersistence.decode(from: SessionPersistence.encode(stored))
        XCTAssertEqual(decoded.segments[0].strokes[0].widthScales, [0.4, 2])
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(decoded)
        let id = restored.orderedStrokes[0].id
        restored.moveSelection([id], by: CGPoint(x: 1000, y: 20))
        let copies = restored.duplicateSelection([id], offset: CGPoint(x: 20, y: 20))
        XCTAssertEqual(restored.orderedStrokes.last?.widthScales, [0.4, 2])
        XCTAssertTrue(copies.contains(restored.orderedStrokes.last!.id))
        restored.undoLastStroke()
        restored.undoLastStroke()
        XCTAssertEqual(restored.orderedStrokes[0].widthScales, [0.4, 2])
        XCTAssertEqual(restored.orderedStrokes[0].points[0], .zero)
    }

    func testLegacyStrokeWithoutProfileKeepsFallbackAndSmallFiles() throws {
        var line = stroke()
        line.widthScales = []
        let state = TapeCanvasSessionState()
        state.commitCompletedStroke(line)
        let session = state.buildStoredSession(contentOffset: .zero, savedAt: 1)
        XCTAssertNil(session.segments[0].strokes[0].widthScales)
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(SessionPersistence.decode(from: SessionPersistence.encode(session)))
        XCTAssertTrue(restored.orderedStrokes[0].widthScales.isEmpty)
        XCTAssertEqual(PencilStrokeWidth.scale(at: 0, in: []), 1)
    }

    func testInvalidWidthProfileRejectedWithoutReplacingCurrentDrawing() throws {
        let state = TapeCanvasSessionState()
        state.commitCompletedStroke(stroke())
        let valid = state.buildStoredSession(contentOffset: .zero, savedAt: 1)
        for invalid in [[CGFloat(1)], [CGFloat.nan, 1], [0.1, 1], [1, 3], []] {
            var session = valid
            session.segments[0].strokes[0].widthScales = invalid
            XCTAssertThrowsError(try state.applyStoredSession(session))
            XCTAssertEqual(state.orderedStrokes[0].widthScales, [0.4, 2])
        }
    }

    func testPressureExpandedBoundsIncludeThickStrokeForVisibilityAndErasing() {
        let state = TapeCanvasSessionState()
        var line = stroke()
        line.lineWidth = 100
        line.widthScales = [2, 2]
        state.commitCompletedStroke(line)
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: 40, y: 110, width: 10, height: 10)).count, 1)
        XCTAssertTrue(state.erase(from: CGPoint(x: 50, y: 110), to: CGPoint(x: 50, y: 110), radius: 1))
        state.endErasing()
        XCTAssertTrue(state.orderedStrokes.isEmpty)
        state.undoLastStroke()
        XCTAssertEqual(state.orderedStrokes[0].widthScales, [2, 2])
    }

    func testPencilDefaultsAreRegisteredAndSensitivityIsRepaired() {
        let suite = "InfinityPaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(9.0, forKey: AppSettings.pencilSensitivity)
        AppSettings.registerDefaults(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: AppSettings.pencilOnly))
        XCTAssertTrue(defaults.bool(forKey: AppSettings.pencilPressure))
        XCTAssertFalse(defaults.bool(forKey: AppSettings.pencilTilt))
        XCTAssertEqual(defaults.double(forKey: AppSettings.pencilSensitivity), 0.5)
    }
}
