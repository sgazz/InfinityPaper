//
//  SessionModel.swift
//  InfinityPaper
//
//  Session types and persistence for production audit (testable, no UIKit).
//

import Foundation

// MARK: - Codable session types (no UIKit dependency)

nonisolated struct StoredSession: Codable, Sendable {
    var segments: [StoredSegment]
    var contentOffset: StoredPoint
    var savedAt: TimeInterval
    var formatVersion: Int? = nil
    var zoomScale: CGFloat? = nil
}

nonisolated struct StoredSegment: Codable, Sendable {
    var id: Int
    var strokes: [StoredStroke]
}

nonisolated struct StoredStroke: Codable, Sendable {
    var points: [StoredPoint]
    var times: [TimeInterval]?
    var color: StoredColor
    var lineWidth: CGFloat
}

nonisolated struct StoredPoint: Codable, Sendable {
    var x: CGFloat
    var y: CGFloat
}

nonisolated struct StoredColor: Codable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
}

// MARK: - Session persistence (sessionURL fallback + encode/decode)

nonisolated enum SessionPersistence {
    static let sessionFileName = "session.json"

    /// Returns document directory URL, or temporary directory if document directory is unavailable.
    static func sessionURL(fileName: String = sessionFileName, fileManager: FileManager = .default) -> URL {
        let directories = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let directory = directories.first ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent(fileName)
    }

    static func encode(_ session: StoredSession) throws -> Data {
        try JSONEncoder().encode(session)
    }

    static func decode(from data: Data) throws -> StoredSession {
        let session = try JSONDecoder().decode(StoredSession.self, from: data)
        try validate(session)
        return session
    }

    enum ValidationError: Error, LocalizedError {
        case unsupportedVersion, invalidDrawing
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: return "This drawing was saved by a newer version of Infinity Paper."
            case .invalidDrawing: return "The saved drawing contains invalid data. A recovery copy is kept on disk."
            }
        }
    }

    static func validate(_ session: StoredSession) throws {
        guard (1...2).contains(session.formatVersion ?? 1) else { throw ValidationError.unsupportedVersion }
        func coordinate(_ value: CGFloat) -> Bool { value.isFinite && abs(value) <= CanvasGeometry.coordinateLimit }
        guard coordinate(session.contentOffset.x), coordinate(session.contentOffset.y), session.savedAt.isFinite,
              session.zoomScale.map({ $0.isFinite && $0 >= CanvasGeometry.minimumZoom && $0 <= 100 }) ?? true,
              Set(session.segments.map(\.id)).count == session.segments.count else { throw ValidationError.invalidDrawing }
        for segment in session.segments {
            for stroke in segment.strokes {
                let color = stroke.color
                guard !stroke.points.isEmpty,
                      stroke.lineWidth.isFinite, stroke.lineWidth > 0, stroke.lineWidth <= 100,
                      [color.red, color.green, color.blue, color.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                      stroke.points.allSatisfy({ coordinate($0.x) && coordinate($0.y) }),
                      stroke.times?.allSatisfy({ $0.isFinite }) ?? true else { throw ValidationError.invalidDrawing }
            }
        }
    }

}
