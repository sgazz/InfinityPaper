import Foundation

/// Owns asynchronous save/load/delete bookkeeping, independently of the drawing view.
final class CanvasPersistenceCoordinator {
    private let state: TapeCanvasSessionState
    private let manager: CanvasSessionManager
    private let makeSnapshot: () -> StoredSession?
    private let shouldDeferActiveSave: () -> Bool
    var onLoaded: ((StoredSession) -> Void)?
    var onSaved: (() -> Void)?
    var onError: ((String) -> Void)?
    private let keepEmptySession: Bool
    private var saveWaiters: [(Result<Void, Error>) -> Void] = []
    var onLoadFinished: ((Bool) -> Void)?
    private var pendingLoadID: UUID?
    private var pendingDeletes = 0
    private var sessionSaveInFlight = false
    private var sessionSaveCoalesceRequested = false
    private var didShowSavedToastThisSession = false

    init(state: TapeCanvasSessionState, manager: CanvasSessionManager = CanvasSessionManager(),
         makeSnapshot: @escaping () -> StoredSession?, shouldDeferActiveSave: @escaping () -> Bool = { false }, keepEmptySession: Bool = false) {
        self.keepEmptySession = keepEmptySession
        self.state = state
        self.manager = manager
        self.makeSnapshot = makeSnapshot
        self.shouldDeferActiveSave = shouldDeferActiveSave
    }

    func start(autoload: Bool? = nil, onResign: @escaping () -> Void) {
        manager.registerForAppLifecycle(
            saveOnResign: { [weak self] in onResign(); self?.save() },
            resumeOnActive: { [weak self] in self?.startTimer() })
        if autoload ?? manager.shouldAutoloadOnLaunch() { load() }
        startTimer()
    }

    private func startTimer() { manager.startPeriodicSaveTimerIfNeeded { [weak self] in self?.save() } }
    func stop() { manager.stopPeriodicSaveTimer(); manager.unregisterFromAppLifecycle() }
    func invalidatePendingLoad() { pendingLoadID = nil }
    func saveBeforeDetaching() {
        guard state.hasUnsavedChanges else { return }
        manager.beginBackgroundPersistence()
        save()
    }

    func saveAndWait(completion: @escaping (Result<Void, Error>) -> Void) {
        saveWaiters.append(completion)
        save()
    }

    private func finishWaiters(_ result: Result<Void, Error>) {
        let callbacks = saveWaiters
        saveWaiters.removeAll()
        callbacks.forEach { $0(result) }
    }

    func save() {
        guard state.hasUnsavedChanges else {
            if !sessionSaveInFlight, pendingDeletes == 0 {
                manager.endBackgroundPersistence()
                finishWaiters(.success(()))
            }
            return
        }
        if sessionSaveInFlight || pendingDeletes > 0 {
            sessionSaveCoalesceRequested = true
            return
        }
        guard let storedSession = makeSnapshot() else {
            manager.endBackgroundPersistence()
            finishWaiters(.failure(CocoaError(.fileWriteUnknown)))
            return
        }
        sessionSaveInFlight = true
        sessionSaveCoalesceRequested = false
        let snapshot = state.persistenceRevision
        manager.saveSession(storedSession) { [weak self] result in
            guard let self else { return }
            self.sessionSaveInFlight = false
            // A clear/load started a different session. Never acknowledge or resubmit that old snapshot.
            guard snapshot.generation == self.state.persistenceRevision.generation else {
                self.sessionSaveCoalesceRequested = false
                if self.state.hasUnsavedChanges { self.save() }
                else { self.manager.endBackgroundPersistence(); self.finishWaiters(.success(())) }
                return
            }
            switch result {
            case .success:
                self.state.acknowledgePersistenceSave(succeededWithRevision: snapshot)
                if !self.didShowSavedToastThisSession {
                    self.didShowSavedToastThisSession = true
                    self.onSaved?()
                }
                if self.shouldDeferActiveSave(), !self.sessionSaveCoalesceRequested, self.saveWaiters.isEmpty {
                    // New samples remain dirty for the next periodic save; do not write once per input frame.
                    self.manager.endBackgroundPersistence()
                } else if self.state.hasUnsavedChanges || self.sessionSaveCoalesceRequested {
                    self.save()
                } else {
                    self.manager.endBackgroundPersistence()
                    self.finishWaiters(.success(()))
                }
            case .failure(let error):
                self.sessionSaveCoalesceRequested = false
                self.onError?(NSLocalizedString("toast.save_failed", comment: "Save failed"))
                self.finishWaiters(.failure(error))
                self.manager.endBackgroundPersistence()
            }
        }
    }

    func load() {
        let request = UUID()
        pendingLoadID = request
        let expectedRevision = state.persistenceRevision
        manager.loadSession { [weak self] result in
            guard let self, self.pendingLoadID == request,
                  self.state.persistenceRevision == expectedRevision else { return }
            self.pendingLoadID = nil
            switch result {
            case .success(let storedSession):
                do {
                    try self.state.applyStoredSession(storedSession)
                    self.onLoaded?(storedSession)
                    self.onLoadFinished?(true)
                } catch { self.onError?(error.localizedDescription); self.onLoadFinished?(false) }
            case .failure(let error):
                self.onLoadFinished?(false)
                if (error as NSError).code != NSFileReadNoSuchFileError {
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func clear() {
        pendingLoadID = nil
        state.clear()
        didShowSavedToastThisSession = false
        if keepEmptySession { save(); return }
        let clearedRevision = state.persistenceRevision
        pendingDeletes += 1
        manager.deleteSession { [weak self] result in
            guard let self else { return }
            self.pendingDeletes -= 1
            switch result {
            case .success:
                self.state.acknowledgePersistenceSave(succeededWithRevision: clearedRevision)
            case .failure:
                self.onError?("Could not remove the saved drawing. Saving the current state instead.")
                self.save()
            }
            if self.pendingDeletes == 0, self.state.hasUnsavedChanges { self.save() }
            else if !self.sessionSaveInFlight, self.pendingDeletes == 0 {
                self.manager.endBackgroundPersistence()
                self.finishWaiters(.success(()))
            }
        }
    }
}
