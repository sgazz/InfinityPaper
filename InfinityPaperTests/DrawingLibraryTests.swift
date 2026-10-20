import XCTest
@testable import InfinityPaper

final class DrawingLibraryTests: XCTestCase {
    private func makeStore() throws -> (DrawingLibraryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (DrawingLibraryStore(root: directory.appendingPathComponent("Drawings"),
                                    legacyURL: directory.appendingPathComponent("session.json")), directory)
    }

    func testMigrationIsIdempotentKeepsOriginalAndDoesNotResurrectDeletion() async throws {
        let (store, directory) = try makeStore()
        let data = try SessionPersistence.encode(StoredSession(segments: [], contentOffset: StoredPoint(x: 12, y: 34), savedAt: 123))
        let legacy = directory.appendingPathComponent("session.json")
        try data.write(to: legacy)
        let first = try await store.list()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.id, DrawingLibraryStore.migratedID)
        XCTAssertEqual(try Data(contentsOf: store.sessionURL(for: first[0].id)), data)
        XCTAssertEqual(try Data(contentsOf: legacy), data)
        let again = try await store.list()
        XCTAssertEqual(again.count, 1)
        try await store.delete(first[0].id)
        let afterDelete = try await store.list()
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacy), data)
    }

    func testCreateRenameDuplicateAndDeleteAreIsolated() async throws {
        let (store, _) = try makeStore()
        _ = try await store.list()
        let a = try await store.create(title: "  First  ")
        let b = try await store.create(title: "Second")
        var session = try SessionPersistence.decode(from: Data(contentsOf: store.sessionURL(for: a.id)))
        session.paperPattern = .grid
        session.paperSpacing = 48
        session.segments = [StoredSegment(id: 0, strokes: [StoredStroke(points: [StoredPoint(x: 10, y: 20)],
            color: StoredColor(red: 0, green: 0, blue: 0, alpha: 1), lineWidth: 2)])]
        try SessionPersistence.encode(session).write(to: store.sessionURL(for: a.id))
        let copy = try await store.duplicate(a.id)
        XCTAssertNotEqual(copy.id, a.id)
        let copied = try SessionPersistence.decode(from: Data(contentsOf: store.sessionURL(for: copy.id)))
        XCTAssertEqual(copied.paperPattern, .grid)
        XCTAssertEqual(copied.paperSpacing, 48)
        XCTAssertEqual(copied.segments[0].strokes[0].points[0].x, 10)
        try await store.rename(a.id, title: "../ renamed")
        let renamed = try await store.open(a.id)
        XCTAssertEqual(renamed.title, "../ renamed")
        try await store.delete(a.id)
        let remaining = try await store.list()
        XCTAssertEqual(Set(remaining.map(\.id)), Set([b.id, copy.id]))
        XCTAssertGreaterThan(remaining.first(where: { $0.id == copy.id })?.previewBounds?.width ?? 0, 1)
        let empty = try SessionPersistence.decode(from: Data(contentsOf: store.sessionURL(for: b.id)))
        XCTAssertTrue(empty.segments.isEmpty)
    }

    func testCorruptDocumentCannotBeOpenedOrDuplicated() async throws {
        let (store, _) = try makeStore()
        let document = try await store.create()
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: store.sessionURL(for: document.id))
        do { _ = try await store.open(document.id); XCTFail("Accepted corrupt drawing") } catch {}
        do { _ = try await store.duplicate(document.id); XCTFail("Duplicated corrupt drawing") } catch {}
        let list = try await store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list[0].previewUnavailable)
        XCTAssertEqual(try Data(contentsOf: store.sessionURL(for: document.id)), corrupt)
    }

    func testPatternRoundtripLegacyFallbackAndInvalidSpacing() throws {
        var session = StoredSession(segments: [], contentOffset: StoredPoint(x: 0, y: 0), savedAt: 1)
        let legacy = try SessionPersistence.decode(from: SessionPersistence.encode(session))
        XCTAssertNil(legacy.paperPattern)
        session.paperPattern = .dots
        session.paperSpacing = 64
        let decoded = try SessionPersistence.decode(from: SessionPersistence.encode(session))
        XCTAssertEqual(decoded.paperPattern, .dots)
        XCTAssertEqual(decoded.paperSpacing, 64)
        session.paperSpacing = 0
        XCTAssertThrowsError(try SessionPersistence.decode(from: SessionPersistence.encode(session)))
        XCTAssertGreaterThanOrEqual(PaperPatternLayout.visibleSpacing(32, zoom: 0.00001) * 0.00001, 8)
        XCTAssertLessThanOrEqual(20_000_000 / PaperPatternLayout.visibleSpacing(32, zoom: 1, extent: 20_000_000), 256)
    }
    func testCorruptLegacyRemainsVisibleWithoutBlockingOtherDrawings() async throws {
        let (store, directory) = try makeStore()
        let data = Data("corrupt legacy".utf8)
        let legacyURL = directory.appendingPathComponent("session.json")
        try data.write(to: legacyURL)
        let imported = try await store.list()
        XCTAssertEqual(imported.count, 1)
        XCTAssertTrue(imported[0].previewUnavailable)
        _ = try await store.create(title: "New work")
        let drawings = try await store.list()
        XCTAssertEqual(drawings.count, 2)
        XCTAssertEqual(try Data(contentsOf: legacyURL), data)
        XCTAssertEqual(try Data(contentsOf: store.sessionURL(for: DrawingLibraryStore.migratedID)), data)
    }

}
