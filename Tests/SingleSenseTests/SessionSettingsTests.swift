import XCTest
@testable import SingleSense

/// The working state that used to be rebuilt from defaults on every launch.
final class SessionSettingsTests: XCTestCase {

    private func roundTrip(_ settings: SessionSettings) throws -> SessionSettings {
        let data = try JSONEncoder().encode(settings)
        return try JSONDecoder().decode(SessionSettings.self, from: data)
    }

    func testEverythingSurvivesARoundTrip() throws {
        var settings = SessionSettings()
        settings.lightbar.mode = .musicSync
        settings.lightbar.musicSyncStyle = .beatFlash
        settings.lightbar.musicHapticsStyle = .fullRange
        settings.lightbar.playerLEDMode = .player3
        settings.lightbar.staticColor = AppColor(red: 0.2, green: 0.4, blue: 0.6)
        settings.leftTrigger = makeTrigger(.weapon) {
            $0.startPosition = 0.25; $0.endPosition = 0.85; $0.strength = 0.9
        }
        settings.rightTrigger = makeTrigger(.machineGun) { $0.strength = 0.7 }
        settings.triggersLinked = true
        settings.leftRumble = 0.35
        settings.activeProfileId = UUID()
        settings.trackpadEnabled = true
        settings.trackpadSensitivity = 2400
        settings.trackpadNaturalScrolling = false

        XCTAssertEqual(try roundTrip(settings), settings)
    }

    /// A file written by an older build is missing keys; it must not throw the
    /// whole session away.
    func testPartialFileFallsBackPerField() throws {
        let json = #"{"triggersLinked": true, "trackpadSensitivity": 2000}"#
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))
        let defaults = SessionSettings()

        XCTAssertTrue(restored.triggersLinked)
        XCTAssertEqual(restored.trackpadSensitivity, 2000)
        XCTAssertEqual(restored.lightbar, defaults.lightbar)
        XCTAssertEqual(restored.leftTrigger, defaults.leftTrigger)
        XCTAssertNil(restored.activeProfileId)
    }

    func testEmptyFileYieldsDefaults() throws {
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(restored, SessionSettings())
    }

    /// A hand-edited file must not push out-of-range values into the driver.
    func testHostileValuesAreClamped() throws {
        let json = """
        {
          "leftRumble": 9.0,
          "rightRumble": -3.0,
          "trackpadSensitivity": 999999,
          "trackpadScrollSensitivity": -50,
          "leftTrigger": { "mode": "Weapon Pull", "strength": 42.0 }
        }
        """
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))
        XCTAssertEqual(restored.leftRumble, 1)
        XCTAssertEqual(restored.rightRumble, 0)
        XCTAssertLessThanOrEqual(restored.trackpadSensitivity, 3200)
        XCTAssertGreaterThanOrEqual(restored.trackpadScrollSensitivity, 200)
        XCTAssertEqual(restored.leftTrigger.strength, 1)
    }

    /// JSON cannot express infinity and JSONDecoder rejects unrepresentable
    /// numbers outright, so the protection against a mangled file lives in the
    /// store rather than in the per-field clamps.
    func testUnreadableFileFallsBackToDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)
        try Data(#"{"trackpadSensitivity": 1e999, "leftRumble":"#.utf8)
            .write(to: directory.appendingPathComponent("session.json"))

        XCTAssertEqual(store.load(), SessionSettings())
    }

    func testSettingsSurviveDiskRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)
        XCTAssertEqual(store.load(), SessionSettings(), "no file yet means defaults")

        var settings = SessionSettings()
        settings.lightbar.mode = .musicSync
        settings.triggersLinked = true
        settings.trackpadEnabled = true
        store.flush(settings)

        XCTAssertEqual(SettingsStore(directory: directory).load(), settings)
    }
}

/// How write failures reach the user.
final class LinkHealthTests: XCTestCase {

    func testOnlyHealthyIsNotAProblem() {
        XCTAssertFalse(LinkHealth.healthy.isProblem)
        XCTAssertTrue(LinkHealth.congested.isProblem)
        XCTAssertTrue(LinkHealth.unresponsive.isProblem)
    }

    func testEveryLevelHasDistinctPresentation() {
        let icons = Set(LinkHealth.allCases.map(\.iconName))
        XCTAssertEqual(icons.count, LinkHealth.allCases.count)
        let labels = Set(LinkHealth.allCases.map(\.rawValue))
        XCTAssertEqual(labels.count, LinkHealth.allCases.count)
    }

    /// The controller stays connected over the same transport even when it is
    /// refusing writes; conflating the two is what the old code did.
    func testLinkHealthIsSeparateFromConnectionType() {
        let state = ControllerState()
        state.isConnected = true
        state.connectionType = .bluetooth
        state.linkHealth = .unresponsive

        XCTAssertEqual(state.connectionType, .bluetooth)
        XCTAssertTrue(state.isConnected)
    }
}
