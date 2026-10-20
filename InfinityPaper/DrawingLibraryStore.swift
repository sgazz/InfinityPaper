import Foundation
import CoreGraphics

nonisolated struct DrawingDocument: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
}

nonisolated struct DrawingSummary: Identifiable, Sendable {
    var id: UUID { document.id }
    let document: DrawingDocument
    let updatedAt: Date
    let preview: [StoredStroke]
    let previewBounds: CGRect?
    let referencePreview: ReferenceImage?
    let previewUnavailable: Bool
}

/// Each drawing owns its session and metadata. All operations share the session IO queue.
nonisolated final class DrawingLibraryStore: @unchecked Sendable {
    static let migratedID = UUID(uuidString: "19E32A54-8539-48ED-8057-0EAF595E81BC")!
    static let activeDrawingKey = "library.activeDrawingID"
    let root: URL
    private let legacyURL: URL
    private let queue: DispatchQueue

    init(root: URL = SessionPersistence.sessionURL().deletingLastPathComponent().appendingPathComponent("Drawings", isDirectory: true),
         legacyURL: URL = SessionPersistence.sessionURL(), queue: DispatchQueue = SessionFileStore.sharedQueue) {
        self.root = root
        self.legacyURL = legacyURL
        self.queue = queue
    }

    func sessionURL(for id: UUID) -> URL { directory(for: id).appendingPathComponent("session.json") }
    private func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: operation)) }
        }
    }

    func list() async throws -> [DrawingSummary] {
        try await perform { [self] in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try migrateLegacyIfNeeded()
            return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                .compactMap { url -> DrawingSummary? in
                    guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
                    let document = try readDocument(id)
                    let session = try? SessionPersistence.decode(from: Data(contentsOf: sessionURL(for: id)))
                    let strokes = session?.segments.flatMap(\.strokes) ?? []
                    var bounds: CGRect?
                    for stroke in strokes {
                        for point in stroke.points {
                            let padding = stroke.lineWidth * PencilStrokeWidth.maximumScale(stroke.widthScales ?? [])
                            let rect = CGRect(x: point.x - padding, y: point.y - padding,
                                              width: 2 * padding, height: 2 * padding)
                            bounds = bounds?.union(rect) ?? rect
                        }
                    }
                    var referencePreview = session?.referenceImage
                    if let reference = referencePreview, reference.isVisible, reference.opacity > 0,
                       let data = ReferenceImageData.preview(reference.imageData) {
                        bounds = bounds?.union(reference.rect) ?? reference.rect
                        referencePreview = ReferenceImage(id: reference.id, imageData: data, x: reference.x, y: reference.y,
                            width: reference.width, height: reference.height, opacity: reference.opacity, isVisible: reference.isVisible)
                    } else { referencePreview = nil }
                    // Keep UI previews small; session files retain every original sample.
                    let preview = strokes.prefix(200).map { stroke -> StoredStroke in
                        var result = stroke
                        let stride = max(1, Int(ceil(Double(stroke.points.count) / 200)))
                        result.points = Swift.stride(from: 0, to: stroke.points.count, by: stride).map { stroke.points[$0] }
                        if let last = stroke.points.last { result.points.append(last) }
                        result.lineWidth *= PencilStrokeWidth.maximumScale(stroke.widthScales ?? [])
                        result.widthScales = nil
                        result.times = nil
                        return result
                    }
                    return DrawingSummary(document: document,
                        updatedAt: session.map { Date(timeIntervalSince1970: $0.savedAt) } ?? document.createdAt,
                        preview: preview, previewBounds: bounds, referencePreview: referencePreview, previewUnavailable: session == nil)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    func create(title: String = "Untitled drawing") async throws -> DrawingDocument {
        try await perform { [self] in
            let document = DrawingDocument(id: UUID(), title: cleanTitle(title), createdAt: Date())
            let session = StoredSession(segments: [], contentOffset: StoredPoint(x: 0, y: 0),
                                       savedAt: Date().timeIntervalSince1970, formatVersion: 2, zoomScale: 1)
            try writeNew(document, sessionData: SessionPersistence.encode(session))
            return document
        }
    }

    func open(_ id: UUID) async throws -> DrawingDocument {
        try await perform { [self] in
            let document = try readDocument(id)
            _ = try SessionPersistence.decode(from: Data(contentsOf: sessionURL(for: id)))
            return document
        }
    }

    func rename(_ id: UUID, title: String) async throws {
        try await perform { [self] in
            var document = try readDocument(id)
            document.title = cleanTitle(title)
            try JSONEncoder().encode(document).write(to: directory(for: id).appendingPathComponent("document.json"), options: .atomic)
        }
    }

    func duplicate(_ id: UUID) async throws -> DrawingDocument {
        try await perform { [self] in
            let original = try readDocument(id)
            var session = try SessionPersistence.decode(from: Data(contentsOf: sessionURL(for: id)))
            session.savedAt = Date().timeIntervalSince1970
            let document = DrawingDocument(id: UUID(), title: cleanTitle(String(original.title.prefix(95)) + " copy"), createdAt: Date())
            try writeNew(document, sessionData: SessionPersistence.encode(session))
            return document
        }
    }

    func delete(_ id: UUID) async throws {
        try await perform { [self] in
            // A tombstone prevents re-importing the legacy file after deleting its migrated drawing.
            if id == Self.migratedID { try writeMigrationMarker() }
            try FileManager.default.removeItem(at: directory(for: id))
        }
    }

    private func readDocument(_ id: UUID) throws -> DrawingDocument {
        let document = try JSONDecoder().decode(DrawingDocument.self,
            from: Data(contentsOf: directory(for: id).appendingPathComponent("document.json")))
        guard document.id == id else { throw CocoaError(.fileReadCorruptFile) }
        return document
    }

    private func cleanTitle(_ title: String) -> String {
        let result = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        return result.isEmpty ? "Untitled drawing" : result
    }

    private var migrationMarker: URL { root.appendingPathComponent(".legacy-imported") }
    private func writeMigrationMarker() throws { try Data().write(to: migrationMarker, options: .atomic) }

    private func migrateLegacyIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: migrationMarker.path) else { return }
        if FileManager.default.fileExists(atPath: directory(for: Self.migratedID).path) {
            try writeMigrationMarker()
            return
        }
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            let data = try Data(contentsOf: legacyURL)
            // Keep even an unreadable legacy drawing visible in the library for recovery.
            // Opening still requires successful validation; neither original is overwritten.
            let session = try? SessionPersistence.decode(from: data)
            let document = DrawingDocument(id: Self.migratedID, title: "My first drawing",
                                           createdAt: session.map { Date(timeIntervalSince1970: $0.savedAt) } ?? Date())
            try writeNew(document, sessionData: data)
        }
        try writeMigrationMarker()
    }

    private func writeNew(_ document: DrawingDocument, sessionData: Data) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".creating-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try sessionData.write(to: staging.appendingPathComponent("session.json"), options: .atomic)
        try JSONEncoder().encode(document).write(to: staging.appendingPathComponent("document.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: directory(for: document.id))
    }
}
