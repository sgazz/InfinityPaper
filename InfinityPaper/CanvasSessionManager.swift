//
//  CanvasSessionManager.swift
//  InfinityPaper
//
//  Manages session persistence (save/load) and autosave behavior for the canvas.
//

import Foundation
import UIKit

/// Manages session persistence and autosave behavior.
final class CanvasSessionManager {
    private var periodicSaveTimer: Timer?
    /// Tokens for block-based `NotificationCenter` observers (must use `removeObserver(_:)` with each token).
    private var appLifecycleObserverTokens: [NSObjectProtocol] = []

    private let periodicSaveInterval: TimeInterval
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    var isPeriodicSaveScheduled: Bool { periodicSaveTimer != nil }

    /// Checks if session should be automatically loaded on launch.
    func shouldAutoloadOnLaunch() -> Bool {
        defaults.bool(forKey: AppSettings.autoload)
    }

    /// Gets the current autosave mode.
    func currentAutosaveMode() -> AutosaveMode {
        let raw = defaults.string(forKey: AppSettings.autosaveMode)
            ?? AppSettings.Default.autosaveMode.rawValue
        return AutosaveMode(rawValue: raw) ?? AppSettings.Default.autosaveMode
    }

    private let store: SessionFileStore
    private var pendingOperations = 0
    private var saveCallback: (() -> Void)?
    private var isActive = true
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(store: SessionFileStore = SessionFileStore(url: SessionPersistence.sessionURL()),
         defaults: UserDefaults = AppSettings.defaults, notificationCenter: NotificationCenter = .default,
         periodicSaveInterval: TimeInterval = 60) {
        self.store = store
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.periodicSaveInterval = periodicSaveInterval
    }

    func saveSession(_ session: StoredSession, completion: @escaping (Result<Void, Error>) -> Void) {
        pendingOperations += 1
        store.save(session) { [self] result in finishOperation(result, completion: completion) }
    }

    func loadSession(completion: @escaping (Result<StoredSession, Error>) -> Void) {
        store.load { result in DispatchQueue.main.async { completion(result) } }
    }

    func deleteSession(completion: @escaping (Result<Void, Error>) -> Void) {
        pendingOperations += 1
        store.delete { [self] result in finishOperation(result, completion: completion) }
    }

    nonisolated private func finishOperation(_ result: Result<Void, Error>, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async { [self] in
            pendingOperations -= 1
            completion(result)
            if pendingOperations == 0 { endBackgroundPersistence() }
        }
    }

    func beginBackgroundPersistence() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save drawing") { [weak self] in
            self?.endBackgroundPersistence(force: true)
        }
    }

    func endBackgroundPersistence(force: Bool = false) {
        guard backgroundTask != .invalid, force || pendingOperations == 0 else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    /// Starts periodic save timer if autosave mode is set to periodic.
    /// - Parameter saveCallback: Called when timer fires to trigger a save
    func startPeriodicSaveTimerIfNeeded(saveCallback: @escaping () -> Void) {
        self.saveCallback = saveCallback
        stopPeriodicSaveTimer()
        guard isActive else { return }
        guard currentAutosaveMode() == .periodic else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: periodicSaveInterval, repeats: true) { _ in
            saveCallback()
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicSaveTimer = timer
    }

    /// Stops the periodic save timer.
    func stopPeriodicSaveTimer() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
    }

    /// Registers for app lifecycle notifications and calls callbacks on the main queue.
    /// Safe to call more than once: removes any previous block observers first.
    /// - Parameters:
    ///   - saveOnResign: Called when app will resign active (for background save)
    ///   - resumeOnActive: Called when app becomes active (to restart timer)
    func registerForAppLifecycle(
        saveOnResign: @escaping () -> Void,
        resumeOnActive: @escaping () -> Void
    ) {
        unregisterFromAppLifecycle()

        let resignToken = notificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isActive = false
            self?.beginBackgroundPersistence()
            saveOnResign()
            self?.stopPeriodicSaveTimer()
        }

        let activeToken = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isActive = true
            resumeOnActive()
        }

        let settingsToken = notificationCenter.addObserver(
            forName: AppSettings.autosaveModeDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let callback = self.saveCallback else { return }
            self.startPeriodicSaveTimerIfNeeded(saveCallback: callback)
        }
        appLifecycleObserverTokens = [resignToken, activeToken, settingsToken]
    }

    /// Removes all block-based app lifecycle observers.
    func unregisterFromAppLifecycle() {
        for token in appLifecycleObserverTokens {
            notificationCenter.removeObserver(token)
        }
        appLifecycleObserverTokens.removeAll()
    }

    deinit {
        stopPeriodicSaveTimer()
        unregisterFromAppLifecycle()
    }
}
