import XCTest
import UIKit
@testable import InfinityPaper

final class CanvasPersistenceCoordinatorTests: XCTestCase {
    private func stroke(_ x: CGFloat) -> TapeSessionStroke {
        TapeSessionStroke(points: [CGPoint(x: x, y: 0), CGPoint(x: x + 20, y: 10)],
                          times: [0, 1], color: UIColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 2)
    }

    func testSaveClearAndNewDrawingKeepOnlyTheNewDrawing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = DispatchQueue(label: "test.coordinator")
        let store = SessionFileStore(url: directory.appendingPathComponent("session.json"), queue: queue)
        let manager = CanvasSessionManager(store: store)
        let state = TapeCanvasSessionState()
        let coordinator = CanvasPersistenceCoordinator(state: state, manager: manager, makeSnapshot: {
            state.buildStoredSession(contentOffset: .zero, savedAt: 123)
        })
        let saved = expectation(description: "current generation saved")
        coordinator.onSaved = { saved.fulfill() }
        coordinator.onError = { XCTFail($0) }
        queue.suspend()
        state.commitCompletedStroke(stroke(0))
        coordinator.save()
        coordinator.clear()
        state.commitCompletedStroke(stroke(1000))
        coordinator.save()
        queue.resume()
        wait(for: [saved], timeout: 5)
        let loaded = expectation(description: "stored drawing")
        manager.loadSession { result in
            switch result {
            case .success(let session): XCTAssertEqual(session.segments[0].strokes.map { $0.points[0].x }, [1000])
            case .failure(let error): XCTFail(error.localizedDescription)
            }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testPendingLoadDoesNotReplaceDrawingCreatedDuringLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let old = TapeCanvasSessionState()
        old.commitCompletedStroke(stroke(0))
        try SessionPersistence.encode(old.buildStoredSession(contentOffset: .zero, savedAt: 1)).write(to: url)
        let queue = DispatchQueue(label: "test.load")
        let manager = CanvasSessionManager(store: SessionFileStore(url: url, queue: queue))
        let state = TapeCanvasSessionState()
        let coordinator = CanvasPersistenceCoordinator(state: state, manager: manager, makeSnapshot: {
            state.buildStoredSession(contentOffset: .zero, savedAt: 2)
        })
        coordinator.onLoaded = { _ in XCTFail("Stale load applied") }
        queue.suspend()
        coordinator.load()
        state.commitCompletedStroke(stroke(1000))
        let drained = expectation(description: "load callbacks drained")
        manager.loadSession { _ in drained.fulfill() }
        queue.resume()
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(state.orderedStrokes.map { $0.points[0].x }, [1000])
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testClearInvalidatesAPendingLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        let state = TapeCanvasSessionState()
        state.commitCompletedStroke(stroke(0))
        try SessionPersistence.encode(state.buildStoredSession(contentOffset: .zero, savedAt: 1)).write(to: url)
        let queue = DispatchQueue(label: "test.clearLoad")
        let manager = CanvasSessionManager(store: SessionFileStore(url: url, queue: queue))
        let coordinator = CanvasPersistenceCoordinator(state: state, manager: manager, makeSnapshot: {
            state.buildStoredSession(contentOffset: .zero, savedAt: 2)
        })
        coordinator.onLoaded = { _ in XCTFail("Load resurrected a cleared drawing") }
        queue.suspend()
        coordinator.load()
        coordinator.clear()
        let drained = expectation(description: "clear and load callbacks drained")
        manager.loadSession { _ in drained.fulfill() }
        queue.resume()
        wait(for: [drained], timeout: 5)
        XCTAssertTrue(state.orderedStrokes.isEmpty)
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
