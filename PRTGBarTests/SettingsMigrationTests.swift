import XCTest
@testable import PRTGBar

final class SettingsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SettingsMigrationTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testMasterOffDisablesAllAlerts() {
        defaults.set(false, forKey: "notifyOnStatusChange")
        defaults.set(true, forKey: "notifyOnDown")
        defaults.set(true, forKey: "notifyOnWarning")

        SettingsMigration.run(defaults)

        XCTAssertEqual(defaults.object(forKey: "notifyOnDown") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "notifyOnWarning") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "notifyOnRecovery") as? Bool, false)
    }

    func testMasterOnKeepsAlertSettings() {
        defaults.set(true, forKey: "notifyOnStatusChange")
        defaults.set(true, forKey: "notifyOnWarning")

        SettingsMigration.run(defaults)

        XCTAssertEqual(defaults.object(forKey: "notifyOnWarning") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "notifyOnRecovery"))
    }

    func testIntervalSnapsToNearest() {
        let cases: [(Double, Double)] = [(40, 30), (100, 120), (1000, 300), (60, 60)]
        for (stored, expected) in cases {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(stored, forKey: "refreshInterval")
            SettingsMigration.run(defaults)
            XCTAssertEqual(defaults.double(forKey: "refreshInterval"), expected, "\(stored)")
        }
    }

    func testRemovesDroppedKeys() {
        for key in ["notifyOnStatusChange", "showAllProbes", "showAcknowledged"] {
            defaults.set(true, forKey: key)
        }

        SettingsMigration.run(defaults)

        for key in ["notifyOnStatusChange", "showAllProbes", "showAcknowledged"] {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), 2)
    }

    func testFreshInstallLeavesDefaultsUnset() {
        SettingsMigration.run(defaults)

        for key in ["notifyOnDown", "notifyOnWarning", "notifyOnRecovery", "refreshInterval"] {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), 2)
    }

    func testInitialTabDependsOnServerURL() {
        XCTAssertEqual(SettingsTab.initial(serverURL: ""), .server)
        XCTAssertEqual(SettingsTab.initial(serverURL: "prtg.example.com"), .general)
    }

    func testIdempotent() {
        defaults.set(false, forKey: "notifyOnStatusChange")
        defaults.set(100.0, forKey: "refreshInterval")
        SettingsMigration.run(defaults)
        XCTAssertEqual(defaults.object(forKey: "notifyOnDown") as? Bool, false)
        XCTAssertEqual(defaults.double(forKey: "refreshInterval"), 120)
        defaults.set(true, forKey: "notifyOnDown")
        defaults.set(45.0, forKey: "refreshInterval")

        SettingsMigration.run(defaults)

        XCTAssertEqual(defaults.object(forKey: "notifyOnDown") as? Bool, true)
        XCTAssertEqual(defaults.double(forKey: "refreshInterval"), 45)
    }
}
