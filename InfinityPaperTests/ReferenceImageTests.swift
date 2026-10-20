import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import InfinityPaper

final class ReferenceImageTests: XCTestCase {
    private func imageData(width: Int = 40, height: Int = 20, type: UTType = .png, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func reference() throws -> ReferenceImage {
        ReferenceImage(id: UUID(), imageData: try imageData(), x: 10, y: 20, width: 200, height: 100)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testImportDownsamplesAndKeepsAspectRatio() throws {
        let url = try temporaryDirectory().appendingPathComponent("large.png")
        try imageData(width: 4096, height: 2048).write(to: url)
        let prepared = try ReferenceImageData.prepare(url: url)
        XCTAssertEqual(prepared.1, CGSize(width: 2048, height: 1024))
        XCTAssertLessThanOrEqual(prepared.0.count, ReferenceImageData.maximumBytes)
        try ReferenceImageData.validate(prepared.0)
    }

    func testImportAppliesPhotoOrientation() throws {
        let url = try temporaryDirectory().appendingPathComponent("rotated.jpg")
        try imageData(width: 40, height: 20, type: .jpeg, orientation: 6).write(to: url)
        let prepared = try ReferenceImageData.prepare(url: url)
        XCTAssertEqual(prepared.1, CGSize(width: 20, height: 40))
        try ReferenceImageData.validate(prepared.0)
    }

    func testInvalidImageDataAndMetadataAreRejected() throws {
        var value = try reference()
        try value.validate()
        for bad in [Data(), Data("not an image".utf8)] { XCTAssertThrowsError(try ReferenceImageData.validate(bad)) }
        value.opacity = 2
        XCTAssertThrowsError(try value.validate())
        value.opacity = 0.5
        value.x = .infinity
        XCTAssertThrowsError(try value.validate())
        value.x = 10
        value.width = -1
        XCTAssertThrowsError(try value.validate())
        XCTAssertThrowsError(try ReferenceImageData.validate(imageData(width: 2049, height: 1)))
    }

    func testFitResizeAndPositionStayWithinValidCoordinates() throws {
        var value = try reference()
        value.fit(in: CGRect(x: 9_999_900, y: -10_000_000, width: 500, height: 500))
        XCTAssertEqual(value.width / value.height, 2, accuracy: 0.0001)
        try value.validate()
        value.resize(by: 100_000)
        value.center(at: CGPoint(x: -10_000_000, y: 10_000_000))
        try value.validate()
        XCTAssertLessThanOrEqual(max(value.width, value.height), 1_000_000)
    }

    func testReferenceRoundtripAndLegacySession() throws {
        let value = try reference()
        let state = TapeCanvasSessionState()
        try state.setReferenceImage(value)
        let data = try SessionPersistence.encode(state.buildStoredSession(contentOffset: .zero, savedAt: 1))
        let restored = TapeCanvasSessionState()
        try restored.applyStoredSession(SessionPersistence.decode(from: data))
        XCTAssertEqual(restored.referenceImage, value)
        let legacy = StoredSession(segments: [], contentOffset: StoredPoint(x: 0, y: 0), savedAt: 1)
        try restored.applyStoredSession(legacy)
        XCTAssertNil(restored.referenceImage)
    }

    func testImportEditRemoveAndUndoRedoKeepIndependentSnapshots() throws {
        let state = TapeCanvasSessionState()
        let original = try reference()
        try state.setReferenceImage(original)
        var edited = original
        edited.opacity = 0.2
        edited.x += 100
        try state.setReferenceImage(edited)
        try state.setReferenceImage(nil)
        XCTAssertNil(state.referenceImage)
        state.undoLastStroke()
        XCTAssertEqual(state.referenceImage, edited)
        state.undoLastStroke()
        XCTAssertEqual(state.referenceImage, original)
        state.undoLastStroke()
        XCTAssertNil(state.referenceImage)
        state.redoLastStroke()
        XCTAssertEqual(state.referenceImage, original)
    }

    func testExportBoundsIncludeOnlyVisibleRequestedReferenceAndClearRemovesIt() throws {
        let state = TapeCanvasSessionState()
        var value = try reference()
        try state.setReferenceImage(value)
        XCTAssertNil(state.worldBoundingRectForExport(currentStroke: nil))
        XCTAssertEqual(state.worldBoundingRectForExport(currentStroke: nil, includeReference: true), value.rect)
        XCTAssertEqual(state.rawWorldBoundingRect(currentStroke: nil), value.rect)
        value.isVisible = false
        try state.setReferenceImage(value)
        XCTAssertNil(state.worldBoundingRectForExport(currentStroke: nil, includeReference: true))
        value.isVisible = true
        value.opacity = 0
        try state.setReferenceImage(value)
        XCTAssertNil(state.worldBoundingRectForExport(currentStroke: nil, includeReference: true))
        state.clear()
        XCTAssertNil(state.referenceImage)
    }

    func testLibraryDuplicateContainsImageWithoutOriginalFileAndHasSmallPreview() async throws {
        let directory = try temporaryDirectory()
        let store = DrawingLibraryStore(root: directory.appendingPathComponent("Drawings"), legacyURL: directory.appendingPathComponent("legacy.json"))
        let document = try await store.create()
        var session = try SessionPersistence.decode(from: Data(contentsOf: store.sessionURL(for: document.id)))
        session.referenceImage = try reference()
        try SessionPersistence.encode(session).write(to: store.sessionURL(for: document.id))
        let copy = try await store.duplicate(document.id)
        try await store.delete(document.id)
        let restored = try SessionPersistence.decode(from: Data(contentsOf: store.sessionURL(for: copy.id)))
        XCTAssertEqual(restored.referenceImage, session.referenceImage)
        let list = try await store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertNotNil(list[0].referencePreview)
        XCTAssertEqual(list[0].previewBounds, session.referenceImage?.rect)
    }
}
