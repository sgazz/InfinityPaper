import XCTest
import UIKit
@testable import InfinityPaper

final class SessionReliabilityTests: XCTestCase {
    private func stroke(_ x: CGFloat = 0, _ end: CGFloat = 20) -> TapeSessionStroke {
        TapeSessionStroke(points: [CGPoint(x: x, y: 0), CGPoint(x: end, y: 10)],
                          times: [0, 1], color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 2)
    }

    private func stored(_ state: TapeCanvasSessionState = TapeCanvasSessionState()) -> StoredSession {
        state.buildStoredSession(contentOffset: CGPoint(x: 12, y: 34), zoomScale: 0.7, savedAt: 123)
    }

    func testOldSaveCannotAcknowledgeNewDrawingAfterClear() {
        let state = TapeCanvasSessionState()
        state.commitCompletedStroke(stroke())
        let old = state.persistenceRevision
        state.clear()
        state.commitCompletedStroke(stroke(100, 110))
        state.acknowledgePersistenceSave(succeededWithRevision: old)
        XCTAssertTrue(state.hasUnsavedChanges)
        XCTAssertNotEqual(old.generation, state.persistenceRevision.generation)
    }

    func testOldSaveCannotAcknowledgeNewDrawingAfterLoad() throws {
        let state = TapeCanvasSessionState()
        state.commitCompletedStroke(stroke())
        let old = state.persistenceRevision
        try state.applyStoredSession(stored())
        state.commitCompletedStroke(stroke(100, 110))
        state.acknowledgePersistenceSave(succeededWithRevision: old)
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testSaveDoesNotAcknowledgeSamplesAddedWhileItWasInFlight() {
        let state = TapeCanvasSessionState()
        state.noteMutationForPersistence()
        let snapshot = state.persistenceRevision
        state.noteMutationForPersistence()
        state.acknowledgePersistenceSave(succeededWithRevision: snapshot)
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testLongStrokeIsVisibleAtItsFarEndOnlyOnce() {
        let state = TapeCanvasSessionState()
        let long = stroke(-2000, 10000)
        state.commitCompletedStroke(long)
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: 9000, y: 0, width: 500, height: 500)).map(\.id), [long.id])
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: -2500, y: 0, width: 15000, height: 1000)).count, 1)
    }

    func testVisibilityIsIndependentOfViewportWidth() {
        let state = TapeCanvasSessionState()
        let line = stroke(1800, 1850)
        state.commitCompletedStroke(line)
        for width: CGFloat in [200, 500, 1200] {
            XCTAssertEqual(state.visibleStrokes(in: CGRect(x: 1750, y: -100, width: width, height: 500)).map(\.id), [line.id])
        }
    }

    func testVisibleAndExportStrokesUseDrawingOrderAcrossColumns() throws {
        let state = TapeCanvasSessionState()
        let first = stroke(1500, 500), second = stroke(500, 1500)
        state.commitCompletedStroke(first)
        state.commitCompletedStroke(second)
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: 0, y: -100, width: 2000, height: 500)).map(\.id), [first.id, second.id])
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(SessionPersistence.decode(from: SessionPersistence.encode(stored(state))))
        XCTAssertEqual(restored.orderedStrokes.map { $0.points.first!.x }, [1500, 500])
    }

    func testUndoLimitKeepsAllRemovedStrokesRecoverable() {
        let state = TapeCanvasSessionState()
        for i in 0..<300 { state.commitCompletedStroke(stroke(CGFloat(i), CGFloat(i + 1))) }
        var undos = 0
        while state.undoLastStroke() { undos += 1 }
        XCTAssertEqual(undos, 256)
        XCTAssertEqual(state.orderedStrokes.count, 44)
        var redos = 0
        while state.redoLastStroke() { redos += 1 }
        XCTAssertEqual(redos, undos)
        XCTAssertEqual(state.orderedStrokes.count, 300)
        XCTAssertEqual(state.orderedStrokes.map { $0.points[0].x }, (0..<300).map(CGFloat.init))
    }

    func testActiveStrokeAndViewportAreIncludedWithoutCommittingStroke() throws {
        let state = TapeCanvasSessionState()
        let snapshot = state.buildStoredSession(contentOffset: CGPoint(x: -150, y: 230), zoomScale: 0.25,
                                                currentStroke: stroke(5, 40), savedAt: 100)
        let decoded = try SessionPersistence.decode(from: SessionPersistence.encode(snapshot))
        XCTAssertEqual(decoded.segments.flatMap(\.strokes).count, 1)
        XCTAssertEqual(decoded.zoomScale, 0.25)
        XCTAssertEqual(decoded.contentOffset.x, -150)
        XCTAssertTrue(state.orderedStrokes.isEmpty)
    }

    func testLegacyFileRebuildsIndexFromCoordinatesInsteadOfSegmentIDs() throws {
        let fixture = """
        {"segments":[{"id":999,"strokes":[{"points":[{"x":1800,"y":0},{"x":2000,"y":10}],"color":{"red":0,"green":0,"blue":0,"alpha":1},"lineWidth":2}]}],"contentOffset":{"x":0,"y":0},"savedAt":1}
        """
        let state = TapeCanvasSessionState()
        try state.applyStoredSession(SessionPersistence.decode(from: Data(fixture.utf8)))
        XCTAssertEqual(state.visibleStrokes(in: CGRect(x: 1700, y: -100, width: 500, height: 500)).count, 1)
    }

    func testInvalidSessionIsRejectedWithoutReplacingCurrentDrawing() {
        let state = TapeCanvasSessionState()
        let line = stroke()
        state.commitCompletedStroke(line)
        var invalid = stored()
        invalid.segments = [StoredSegment(id: 1, strokes: []), StoredSegment(id: 1, strokes: [])]
        XCTAssertThrowsError(try state.applyStoredSession(invalid))
        XCTAssertEqual(state.orderedStrokes.map(\.id), [line.id])
    }

    func testFutureVersionIsRejected() {
        var session = stored()
        session.formatVersion = 100
        XCTAssertThrowsError(try SessionPersistence.decode(from: SessionPersistence.encode(session)))
    }

    func testSaveDeleteOrderingCannotResurrectDeletedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let queue = DispatchQueue(label: "test.sessionOrdering")
        let store = SessionFileStore(url: url, queue: queue)
        let done = expectation(description: "ordered operations")
        queue.suspend()
        store.save(stored()) { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        store.delete { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        store.load { result in
            if case .success = result { XCTFail("Deleted drawing was resurrected") }
            done.fulfill()
        }
        queue.resume()
        wait(for: [done], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testNewSaveAfterDeletePreservesOnlyNewDrawing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionFileStore(url: directory.appendingPathComponent("session.json"))
        let old = TapeCanvasSessionState(), new = TapeCanvasSessionState()
        old.commitCompletedStroke(stroke(1, 2))
        new.commitCompletedStroke(stroke(100, 200))
        let done = expectation(description: "new drawing")
        store.save(stored(old)) { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        store.delete { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        store.save(stored(new)) { if case .failure(let error) = $0 { XCTFail(error.localizedDescription) } }
        store.load { result in
            switch result {
            case .success(let session): XCTAssertEqual(session.segments[0].strokes[0].points[0].x, 100)
            case .failure(let error): XCTFail(error.localizedDescription)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testLegacyFileIsBackedUpBeforeFirstVersionTwoSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        var legacy = stored()
        legacy.formatVersion = nil
        legacy.zoomScale = nil
        let original = try SessionPersistence.encode(legacy)
        try original.write(to: url)
        let store = SessionFileStore(url: url)
        let done = expectation(description: "migration backup")
        store.save(stored()) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let backup = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("session-before-upgrade-") }
        XCTAssertEqual(backup.count, 1)
        XCTAssertEqual(try Data(contentsOf: backup[0]), original)
        XCTAssertEqual(try SessionPersistence.decode(from: Data(contentsOf: url)).formatVersion, 2)
    }

    func testCorruptFileGetsRecoveryCopyBeforeItCanBeReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let corrupt = Data("broken JSON".utf8)
        try corrupt.write(to: url)
        let store = SessionFileStore(url: url)
        let done = expectation(description: "recovery")
        store.load { result in
            if case .success = result { XCTFail("Corrupt data accepted") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let recovery = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("session-recovery-") }
        XCTAssertEqual(recovery.count, 1)
        XCTAssertEqual(try Data(contentsOf: recovery[0]), corrupt)
    }
}
