import Foundation

/// Every file operation uses one ordered queue, including deletion and recovery copies.
nonisolated final class SessionFileStore: @unchecked Sendable {
    static let sharedQueue = DispatchQueue(label: "com.infinitypaper.sessionIO", qos: .utility)
    private let url: URL
    private let queue: DispatchQueue
    private var checkedOriginalBackup = false

    init(url: URL, queue: DispatchQueue = SessionFileStore.sharedQueue) {
        self.url = url
        self.queue = queue
    }

    func save(_ session: StoredSession, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            completion(Result {
                try SessionPersistence.validate(session)
                if !checkedOriginalBackup, FileManager.default.fileExists(atPath: url.path) {
                    let original = try Data(contentsOf: url)
                    let version = (try? SessionPersistence.decode(from: original).formatVersion) ?? 1
                    if version < 2 {
                        let backup = url.deletingLastPathComponent().appendingPathComponent("session-before-upgrade-\(UUID().uuidString).json")
                        try FileManager.default.copyItem(at: url, to: backup)
                    }
                }
                checkedOriginalBackup = true
                let data = try SessionPersistence.encode(session)
                try data.write(to: url, options: .atomic)
            })
        }
    }

    func load(completion: @escaping @Sendable (Result<StoredSession, Error>) -> Void) {
        queue.async { [url] in
            completion(Result {
                let data = try Data(contentsOf: url)
                do {
                    return try SessionPersistence.decode(from: data)
                } catch {
                    // Preserve the original bytes before a later drawing can replace a corrupt file.
                    let recovery = url.deletingLastPathComponent().appendingPathComponent("session-recovery-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: url, to: recovery)
                    throw error
                }
            })
        }
    }

    func delete(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { [url] in
            completion(Result {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            })
        }
    }
}
