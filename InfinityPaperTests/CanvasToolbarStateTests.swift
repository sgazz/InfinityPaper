import XCTest
import Combine
import UIKit
@testable import InfinityPaper

final class CanvasToolbarStateTests: XCTestCase {
    @MainActor private final class Source: CanvasToolbarStateProviding {
        var toolbarState = CanvasToolbarState()
    }

    @MainActor private func drainMainQueue() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @MainActor func testSynchronizationIsDeferredAndPublishesOnlyTheLatestCompleteSnapshot() async {
        let source = Source()
        let broker = CanvasToolbarStateBroker()
        var updates: [CanvasToolbarState] = []
        let token = broker.$state.dropFirst().sink { updates.append($0) }
        defer { token.cancel() }
        broker.attach(source)
        source.toolbarState.canvasReady = true
        source.toolbarState.selectedTool = .lasso
        source.toolbarState.selectedStrokeCount = 3
        source.toolbarState.undoEnabled = true
        source.toolbarState.palette = [.red]
        for _ in 0..<20 { broker.syncFromCanvas() }
        XCTAssertTrue(updates.isEmpty)
        await drainMainQueue()
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0], source.toolbarState)
        for _ in 0..<20 { broker.syncFromCanvas() }
        await drainMainQueue()
        XCTAssertEqual(updates.count, 1, "Unchanged state must not redraw the toolbar")
    }

    @MainActor func testBrokerDoesNotRetainCanvasSourceAndResetsEveryField() async {
        let broker = CanvasToolbarStateBroker()
        var source: Source? = Source()
        weak let weakSource = source
        source?.toolbarState.canvasReady = true
        source?.toolbarState.selectedTool = .eraser
        source?.toolbarState.palette = [.red]
        source?.toolbarState.selectedStrokeCount = 4
        broker.attach(source!)
        await drainMainQueue()
        XCTAssertTrue(broker.state.canvasReady)
        source = nil
        XCTAssertNil(weakSource)
        broker.syncFromCanvas()
        await drainMainQueue()
        XCTAssertEqual(broker.state, CanvasToolbarState())
    }

    @MainActor func testReattachingWhileSyncIsQueuedUsesTheNewSource() async {
        let first = Source(), second = Source()
        first.toolbarState.selectedTool = .eraser
        second.toolbarState.selectedTool = .lasso
        second.toolbarState.selectedStrokeCount = 2
        let broker = CanvasToolbarStateBroker()
        broker.attach(first)
        broker.attach(second)
        await drainMainQueue()
        XCTAssertEqual(broker.state, second.toolbarState)
    }

    @MainActor func testMoreMenuKeepsLibraryAvailableAndOnlyClearIsDestructive() {
        let actions = CanvasToolbarMoreCommand.allCases
        XCTAssertEqual(actions.filter { !$0.requiresCanvas }, [.drawings])
        XCTAssertEqual(actions.filter(\.isDestructive), [.clear])
        XCTAssertEqual(Set(actions.map(\.rawValue)).count, actions.count)
    }
}
