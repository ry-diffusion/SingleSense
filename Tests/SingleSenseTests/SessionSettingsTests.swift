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
        settings.lightbar.mode = .rainbow
        settings.lightbar.playerLEDMode = .player3
        settings.musicSync.isEnabled = true
        settings.musicSync.lightbarStyle = .beatFlash
        settings.musicSync.hapticsStyle = .fullRange
        settings.musicSync.hapticsIntensity = 0.8
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
        XCTAssertEqual(restored.musicSync, defaults.musicSync)
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
        settings.musicSync.isEnabled = true
        settings.triggersLinked = true
        settings.trackpadEnabled = true
        store.flush(settings)

        XCTAssertEqual(SettingsStore(directory: directory).load(), settings)
    }
}

/// Music Sync used to live inside the lightbar configuration, expressed as a
/// lighting mode. A setup saved before the split has to survive it.
final class MusicSyncMigrationTests: XCTestCase {

    /// The old shape: the feature was on because the *mode* said so, and every
    /// setting sat next to the lightbar's own.
    private let legacyLightbar = """
    {
      "mode": "Music Sync",
      "staticColor": { "red": 0.2, "green": 0.4, "blue": 0.6 },
      "rainbowSpeed": 1, "rainbowSaturation": 1, "rainbowBrightness": 1,
      "breathingSpeed": 1,
      "playerLEDMode": "Player 3 (Three LEDs)",
      "playerLEDBrightness": "Medium",
      "micLEDMode": "Off",
      "musicSyncStyle": "Beat Flash",
      "playerLEDAudioStyle": "VU Meter",
      "musicHapticsStyle": "Full Range",
      "musicHapticsIntensity": 0.8,
      "audioSensitivity": 2.5,
      "audioSmoothing": 0.1,
      "audioMinimumBrightness": 0.2
    }
    """

    func testALegacySessionKeepsItsMusicSyncSetup() throws {
        let json = #"{"lightbar": \#(legacyLightbar), "triggersLinked": true}"#
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))

        XCTAssertTrue(restored.musicSync.isEnabled, "it was the active lighting mode, so it was on")
        XCTAssertTrue(restored.musicSync.drivesLightbar, "it used to be the only thing it could drive")
        XCTAssertEqual(restored.musicSync.lightbarStyle, .beatFlash)
        XCTAssertEqual(restored.musicSync.playerLEDStyle, .vuMeter)
        XCTAssertEqual(restored.musicSync.hapticsStyle, .fullRange)
        XCTAssertEqual(restored.musicSync.hapticsIntensity, 0.8, accuracy: 0.0001)
        XCTAssertEqual(restored.musicSync.sensitivity, 2.5, accuracy: 0.0001)
        XCTAssertEqual(restored.musicSync.smoothing, 0.1, accuracy: 0.0001)
        XCTAssertEqual(restored.musicSync.minimumBrightness, 0.2, accuracy: 0.0001)

        // The rest of the lightbar comes across untouched, on a mode the bar
        // can actually show once the music stops.
        XCTAssertNotEqual(restored.lightbar.mode, .musicSync)
        XCTAssertEqual(restored.lightbar.playerLEDMode, .player3)
        XCTAssertTrue(restored.triggersLinked)
    }

    /// Every legacy key was written with a default whether or not the feature
    /// was ever used, so only the old mode may switch it on.
    func testALegacySessionOnAnotherModeDoesNotSwitchMusicSyncOn() throws {
        let json = #"{"lightbar": \#(legacyLightbar.replacingOccurrences(of: "Music Sync", with: "60 FPS Rainbow"))}"#
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))

        XCTAssertFalse(restored.musicSync.isEnabled)
        XCTAssertEqual(restored.lightbar.mode, .rainbow)
        // The tuning is still carried over, ready for when it is switched on.
        XCTAssertEqual(restored.musicSync.hapticsStyle, .fullRange)
    }

    func testALegacyProfileKeepsItsMusicSyncSetup() throws {
        let json = #"""
        {
          "id": "8B2C1E64-0000-4000-8000-000000000001",
          "name": "Night Drive",
          "description": "",
          "iconName": "car.fill",
          "lightbar": \#(legacyLightbar),
          "leftTrigger": { "mode": "Off / Standard" },
          "rightTrigger": { "mode": "Off / Standard" },
          "triggersLinked": false,
          "leftRumble": 0,
          "rightRumble": 0,
          "createdAt": 0,
          "updatedAt": 0
        }
        """#
        let profile = try JSONDecoder().decode(ControllerProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.name, "Night Drive")
        XCTAssertTrue(profile.musicSync.isEnabled)
        XCTAssertEqual(profile.musicSync.lightbarStyle, .beatFlash)
        XCTAssertEqual(profile.musicSync.playerLEDStyle, .vuMeter)
        XCTAssertNotEqual(profile.lightbar.mode, .musicSync)
    }

    /// Newer files carry their own key, which must win over the legacy fields.
    func testAStoredConfigurationWinsOverTheLegacyFields() throws {
        let json = #"""
        {
          "lightbar": \#(legacyLightbar),
          "musicSync": { "isEnabled": false, "lightbarStyle": "Spectrum", "hapticsStyle": "Off" }
        }
        """#
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))

        XCTAssertFalse(restored.musicSync.isEnabled)
        XCTAssertEqual(restored.musicSync.lightbarStyle, .spectrum)
        XCTAssertEqual(restored.musicSync.hapticsStyle, .off)
    }

    /// A hand-edited file must not push out-of-range values into the analysis.
    func testHostileMusicSyncValuesAreClamped() throws {
        let json = """
        {
          "musicSync": {
            "isEnabled": true,
            "hapticsIntensity": 42,
            "sensitivity": -8,
            "smoothing": 99,
            "minimumBrightness": 5,
            "lightbarStyle": "not a style"
          }
        }
        """
        let restored = try JSONDecoder().decode(SessionSettings.self, from: Data(json.utf8))
        let defaults = MusicSyncConfiguration()

        XCTAssertTrue(restored.musicSync.isEnabled)
        XCTAssertEqual(restored.musicSync.hapticsIntensity, 1)
        XCTAssertEqual(restored.musicSync.sensitivity, 0.25)
        XCTAssertEqual(restored.musicSync.smoothing, 1)
        XCTAssertEqual(restored.musicSync.minimumBrightness, 0.5)
        XCTAssertEqual(restored.musicSync.lightbarStyle, defaults.lightbarStyle,
                       "an unknown style falls back rather than throwing the file away")
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
