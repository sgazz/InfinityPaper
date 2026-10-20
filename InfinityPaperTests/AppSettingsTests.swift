import XCTest
@testable import InfinityPaper

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchExistingInstallationBehavior() {
        let suite = "InfinityPaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        AppSettings.registerDefaults(in: defaults)
        XCTAssertEqual(defaults.double(forKey: AppSettings.resolution), 2)
        XCTAssertEqual(defaults.double(forKey: AppSettings.lineWidth), 2.5)
        XCTAssertTrue(defaults.bool(forKey: AppSettings.includeNoise))
        XCTAssertTrue(defaults.bool(forKey: AppSettings.autoName))
        XCTAssertTrue(defaults.bool(forKey: AppSettings.autoload))
        XCTAssertFalse(defaults.bool(forKey: AppSettings.transparent))
        XCTAssertEqual(defaults.string(forKey: AppSettings.exportFormat), "pdf")
    }

    func testRegistrationPreservesPreferencesSavedUnderExistingKeys() {
        let suite = "InfinityPaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "settings.session.autoload")
        defaults.set(4.0, forKey: "settings.export.resolution")
        defaults.set("png", forKey: "settings.export.format")
        AppSettings.registerDefaults(in: defaults)
        AppSettings.registerDefaults(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: AppSettings.autoload))
        XCTAssertEqual(defaults.double(forKey: AppSettings.resolution), 4)
        XCTAssertEqual(defaults.string(forKey: AppSettings.exportFormat), "png")
    }

    func testInvalidNumericPreferencesAreRepaired() {
        let suite = "InfinityPaperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-5.0, forKey: AppSettings.resolution)
        defaults.set(1000.0, forKey: AppSettings.lineWidth)
        defaults.set(-2.0, forKey: AppSettings.margin)
        AppSettings.registerDefaults(in: defaults)
        XCTAssertEqual(defaults.double(forKey: AppSettings.resolution), 2)
        XCTAssertEqual(defaults.double(forKey: AppSettings.lineWidth), 2.5)
        XCTAssertEqual(defaults.double(forKey: AppSettings.margin), 0)
    }

}
