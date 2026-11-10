import SwiftUI

/// Music Sync as a feature in its own right.
///
/// It is not a lighting mode: the analysis can drive the light bar, the player
/// indicator row and the rumble motors, each independently, while the light bar
/// keeps whatever mode is set in Lightbar for when the music stops.
public struct MusicSyncView: View {
    @ObservedObject var manager = DualSenseManager.shared
    @ObservedObject var audioEngine = AudioReactiveEngine.shared
    @ObservedObject var coils = VoiceCoilEngine.shared

    @State private var hexInput: String = ""

    public init() {}

    private var music: MusicSyncConfiguration { manager.musicSyncConfig }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                masterSwitch
                if case .permissionRequired = audioEngine.status { permissionCallout }
                if case .relaunchRequired = audioEngine.status { relaunchCallout }
                if case .failed(let message) = audioEngine.status {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                liveSpectrum

                VStack(spacing: 16) {
                    lightbarSection
                    playerIndicatorSection
                    hapticsSection
                    tuningSection
                }
                .disabled(!music.isEnabled)
                .opacity(music.isEnabled ? 1 : 0.55)
            }
            .padding(20)
        }
        .onAppear {
            hexInput = manager.lightbarConfig.staticColor.hexString
        }
    }

    // MARK: - Master switch

    @ViewBuilder
    private var masterSwitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(isOn: Binding(
                    get: { manager.musicSyncConfig.isEnabled },
                    set: { newValue in
                        manager.musicSyncConfig.isEnabled = newValue
                        manager.applyMusicSyncConfiguration(force: true)
                    }
                )) {
                    Text("Music Sync")
                        .font(.headline.weight(.bold))
                }
                .toggleStyle(.switch)

                Spacer()

                captureStatusBadge
            }

            Text("Reads the system audio mix through Core Audio, so it follows whatever is playing — Spotify, Apple Music, a browser tab or a game. Pick below which parts of the controller it drives.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                channelPill("Light bar", "sparkles", music.isDrivingLightbar)
                channelPill("Player LEDs", "circle.grid.2x1.fill", music.isDrivingPlayerLEDs)
                channelPill("Rumble", "waveform.path", music.isDrivingRumble)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    /// At-a-glance summary of what the music is actually taking over, so the
    /// answer does not depend on reading three sections.
    private func channelPill(_ title: String, _ icon: String, _ active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: active ? icon : "circle.slash")
                .font(.caption)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(active ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.12))
        )
        .foregroundColor(active ? .white : .secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "driven by the music" : "not driven by the music")
    }

    // MARK: - Light bar

    @ViewBuilder
    private var lightbarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { manager.musicSyncConfig.drivesLightbar },
                set: { newValue in
                    manager.musicSyncConfig.drivesLightbar = newValue
                    manager.applyMusicSyncConfiguration(force: true)
                }
            )) {
                Text("Drive the light bar")
                    .font(.headline.weight(.bold))
            }
            .toggleStyle(.switch)

            Text("While this is on the music takes the bar over from the lighting mode; turn it off to keep your static colour, rainbow or breathing and let the music drive only the LEDs and the motors.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                ForEach(MusicSyncStyle.allCases) { style in
                    let selected = music.lightbarStyle == style
                    Button(action: {
                        manager.musicSyncConfig.lightbarStyle = style
                        manager.applyMusicSyncConfiguration()
                    }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(style.rawValue)
                                .font(.callout.weight(.semibold))
                                .foregroundColor(selected ? .white : .primary)
                            Text(style.detail)
                                .font(.caption)
                                .foregroundColor(selected ? .white.opacity(0.85) : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Color.accentColor : Color.secondary.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .disabled(!music.drivesLightbar)
            .opacity(music.drivesLightbar ? 1 : 0.55)

            if music.lightbarStyle == .pulse || music.lightbarStyle == .beatFlash {
                Divider()

                // The same colour the light bar uses outside Music Sync: these
                // two styles tint it rather than deriving a hue of their own.
                HStack {
                    Text("Base Colour")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(manager.lightbarConfig.staticColor.hexString)
                        .font(.subheadline.monospaced().weight(.bold))
                        .foregroundColor(.secondary)
                }

                RGBColorSlidersView(color: $manager.lightbarConfig.staticColor) { _ in
                    hexInput = manager.lightbarConfig.staticColor.hexString
                }
                ColorPresetsGridView(selectedColor: $manager.lightbarConfig.staticColor) { newColor in
                    hexInput = newColor.hexString
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Player indicator row

    @ViewBuilder
    private var playerIndicatorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Player Indicator LEDs")
                    .font(.headline.weight(.bold))
                Spacer()
                indicatorPreview
            }

            Picker("", selection: Binding(
                get: { manager.musicSyncConfig.playerLEDStyle },
                set: { newValue in
                    manager.musicSyncConfig.playerLEDStyle = newValue
                    manager.applyMusicSyncConfiguration()
                }
            )) {
                ForEach(PlayerLEDAudioStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            Text(music.playerLEDStyle.detail)
                .font(.caption)
                .foregroundColor(.secondary)

            if music.playerLEDStyle == .fixed {
                Text("The row keeps the pattern set in Lightbar & LEDs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Rumble

    @ViewBuilder
    private var hapticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rumble")
                    .font(.headline.weight(.bold))
                Spacer()
                motorPreview
            }

            Picker("", selection: Binding(
                get: { manager.musicSyncConfig.hapticsStyle },
                set: { newValue in
                    manager.musicSyncConfig.hapticsStyle = newValue
                    manager.applyMusicSyncConfiguration()
                }
            )) {
                ForEach(MusicHapticsStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            Text(music.hapticsOnVoiceCoils && coils.status.canPlay
                 ? music.hapticsStyle.coilDetail
                 : music.hapticsStyle.detail)
                .font(.caption)
                .foregroundColor(.secondary)

            if music.hapticsStyle != .off {
                Toggle(isOn: Binding(
                    get: { manager.musicSyncConfig.hapticsOnVoiceCoils },
                    set: { newValue in
                        manager.musicSyncConfig.hapticsOnVoiceCoils = newValue
                        manager.applyMusicSyncConfiguration()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feel it through the voice coils")
                            .font(.callout.weight(.medium))
                        Text(coils.status.canPlay
                             ? "The music itself goes to the actuators in the grips — the bass line, not just its level. The motors stay out of it."
                             : "Needs a USB cable. Until then the motors carry the music.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Intensity Ceiling")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(Int(music.hapticsIntensity * 100))%")
                            .font(.callout.monospaced().weight(.bold))
                    }
                    Slider(value: $manager.musicSyncConfig.hapticsIntensity, in: 0.0...1.0) { _ in
                        manager.applyMusicSyncConfiguration()
                    }
                    Text("How much of the motors the loudest passage is allowed to use — the music decides how much of that ceiling it reaches, moment to moment.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Continuous rumble drains the controller noticeably faster.",
                      systemImage: "battery.25")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("While this is on the music overrides the manual rumble sliders in Haptics & Vibration.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Tuning

    @ViewBuilder
    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis")
                .font(.headline.weight(.bold))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sensitivity")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(String(format: "%.2fx", music.sensitivity))
                        .font(.callout.monospaced().weight(.bold))
                }
                Slider(value: $manager.musicSyncConfig.sensitivity, in: 0.25...4.0, step: 0.05) { _ in
                    manager.applyMusicSyncConfiguration()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Smoothing")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(music.smoothing * 100))%")
                        .font(.callout.monospaced().weight(.bold))
                }
                Slider(value: $manager.musicSyncConfig.smoothing, in: 0.0...1.0) { _ in
                    manager.applyMusicSyncConfiguration()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Floor Brightness")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(music.minimumBrightness * 100))%")
                        .font(.callout.monospaced().weight(.bold))
                }
                Slider(value: $manager.musicSyncConfig.minimumBrightness, in: 0.0...0.5)
                Text("Keeps the bar from going fully dark between phrases.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Status and meters

    @ViewBuilder
    private var captureStatusBadge: some View {
        let descriptor: (String, Color) = {
            switch audioEngine.status {
            case .idle: return ("Idle", .secondary)
            case .starting: return ("Starting…", .orange)
            case .running: return ("Listening", .green)
            case .permissionRequired: return ("Permission needed", .orange)
            case .relaunchRequired: return ("Relaunch needed", .orange)
            case .failed: return ("Error", .red)
            }
        }()

        HStack(spacing: 5) {
            Circle().fill(descriptor.1).frame(width: 7, height: 7)
            Text(descriptor.0)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(descriptor.1)
        }
    }

    @ViewBuilder
    private var liveSpectrum: some View {
        let levels = audioEngine.displayLevels
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Spectrum")
                .font(.headline.weight(.bold))
            VStack(spacing: 6) {
                meterRow("Bass", levels.bass, .red)
                meterRow("Mid", levels.mid, .green)
                meterRow("Treble", levels.treble, .blue)
                meterRow("Beat", levels.beat, .purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func meterRow(_ title: String, _ value: Float, _ tint: Color) -> some View {
        let clamped = CGFloat(max(0, min(1, value)))
        return HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 46, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(tint).frame(width: clamped * geo.size.width)
                }
            }
            .frame(height: 8)
            Text("\(Int(clamped * 100))%")
                .font(.caption.monospaced().weight(.bold))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }

    /// Mirrors the row the controller is showing, resolved through the very
    /// same function that fills the output report.
    @ViewBuilder
    private var indicatorPreview: some View {
        let levels = audioEngine.displayLevels
        let mask = manager.lightbarConfig.playerLEDMask(
            music: music, level: levels.overall, beat: levels.beat
        )
        let litCount = (0..<PlayerLEDIndicator.lampCount)
            .filter { (mask >> UInt8($0)) & 1 == 1 }.count
        HStack(spacing: 5) {
            ForEach(0..<PlayerLEDIndicator.lampCount, id: \.self) { index in
                let lit = (mask >> UInt8(index)) & 1 == 1
                Circle()
                    .fill(lit ? Color.white : Color.secondary.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .shadow(color: lit ? .white.opacity(0.8) : .clear, radius: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Player indicator preview")
        .accessibilityValue("\(litCount) of \(PlayerLEDIndicator.lampCount) lamps lit")
    }

    /// Live motor levels, resolved through the same function that fills the
    /// rumble bytes in the output report.
    @ViewBuilder
    private var motorPreview: some View {
        let levels = audioEngine.displayLevels
        let motors = music.rumble(
            bass: levels.bass, mid: levels.mid, treble: levels.treble, beat: levels.beat
        )
        HStack(spacing: 8) {
            motorPip("L", motors.left)
            motorPip("R", motors.right)
        }
    }

    private func motorPip(_ label: String, _ value: Float) -> some View {
        let clamped = CGFloat(max(0, min(1, value)))
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundColor(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 34, height: 6)
                Capsule().fill(Color.orange).frame(width: 34 * clamped, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label == "L" ? "Left motor" : "Right motor")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System Audio Recording Required", systemImage: "waveform.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)

            Text("Single Sense reads the system audio output in memory to synchronize controller lighting and haptics. No video or screen is accessed, and audio is never recorded or transmitted.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Request Access") {
                    audioEngine.requestPermission()
                }
                .buttonStyle(.borderedProminent)

                Button("Open System Settings") {
                    audioEngine.openPrivacySettings()
                }
            }
            .controlSize(.small)

            Text("In System Settings, go to Privacy & Security → System Audio Recording Only and turn on Single Sense.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    /// Shown once the permission is ticked in System Settings but this process still
    /// cannot use it, which is every time the grant arrives after launch.
    @ViewBuilder
    private var relaunchCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Relaunch Required", systemImage: "arrow.clockwise.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)

            Text("Screen Recording has been allowed, but macOS requires reopening Single Sense before audio capture can start.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Relaunch Single Sense") {
                    audioEngine.relaunchApp()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}

