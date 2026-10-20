import XCTest
import UIKit
@testable import InfinityPaper

final class AutosaveLifecycleTests: XCTestCase {
    func testModeChangeImmediatelyStartsAndStopsTimerWithoutAppRestart() {
        let suite = "InfinityPaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        AppSettings.registerDefaults(in: defaults)
        let center = NotificationCenter()
        let manager = CanvasSessionManager(defaults: defaults, notificationCenter: center, periodicSaveInterval: 0.01)
        manager.registerForAppLifecycle(saveOnResign: {}, resumeOnActive: {})
        let saved = expectation(description: "periodic save fired")
        saved.assertForOverFulfill = false
        manager.startPeriodicSaveTimerIfNeeded { saved.fulfill() }
        XCTAssertFalse(manager.isPeriodicSaveScheduled)
        defaults.set(AutosaveMode.periodic.rawValue, forKey: AppSettings.autosaveMode)
        center.post(name: AppSettings.autosaveModeDidChange, object: nil)
        XCTAssertTrue(manager.isPeriodicSaveScheduled)
        wait(for: [saved], timeout: 2)
        defaults.set(AutosaveMode.onBackground.rawValue, forKey: AppSettings.autosaveMode)
        center.post(name: AppSettings.autosaveModeDidChange, object: nil)
        XCTAssertFalse(manager.isPeriodicSaveScheduled)
    }

    func testSettingsCannotRestartPeriodicTimerWhileAppIsInactive() {
        let suite = "InfinityPaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        AppSettings.registerDefaults(in: defaults)
        let center = NotificationCenter()
        let manager = CanvasSessionManager(defaults: defaults, notificationCenter: center)
        manager.registerForAppLifecycle(saveOnResign: { [weak manager] in manager?.endBackgroundPersistence() }, resumeOnActive: {})
        manager.startPeriodicSaveTimerIfNeeded {}
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        defaults.set(AutosaveMode.periodic.rawValue, forKey: AppSettings.autosaveMode)
        center.post(name: AppSettings.autosaveModeDidChange, object: nil)
        XCTAssertFalse(manager.isPeriodicSaveScheduled)
    }
}
