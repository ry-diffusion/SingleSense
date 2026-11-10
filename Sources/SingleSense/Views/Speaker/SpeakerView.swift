import SwiftUI

/// Plays the Mac's sound through the controller's speaker, or through
/// headphones plugged into its jack.
public struct SpeakerView: View {
    @ObservedObject var manager = DualSenseManager.shared
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState
    @ObservedObject var engine = ControllerSpeakerEngine.shared
    @ObservedObject var coils = VoiceCoilEngine.shared

    public init() {}

    private var speaker: SpeakerConfiguration { manager.speakerConfig }
    private var subwoofer: SubwooferConfiguration { manager.subwooferConfig }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                masterSwitch
                if speaker.isEnabled || subwoofer.isEnabled { statusCallout }

                VStack(spacing: 16) {
                    volumeSection
                    outputSection
                }
                .disabled(!speaker.isEnabled)
                .opacity(speaker.isEnabled ? 1 : 0.55)

                subwooferSection
            }
            .padding(20)
        }
    }

    // MARK: - Master switch

    private var masterSwitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(isOn: Binding(
                    get: { manager.speakerConfig.isEnabled },
                    set: { newValue in
                        manager.speakerConfig.isEnabled = newValue
                        manager.applySpeakerConfiguration(force: true)
                    }
                )) {
                    Text("Use the Controller as a Speaker")
                        .font(.headline.weight(.bold))
                }
                .toggleStyle(.switch)

                Spacer()

                statusBadge
            }

            Text("Moves whatever your Mac is playing to the controller. The sound is moved, not copied: the Mac's own output goes quiet while this is on, and comes back as soon as you switch it off.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Needs a USB cable. Over Bluetooth macOS doesn't see the controller as a sound device.", systemImage: "cable.connector")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private var statusBadge: some View {
        let descriptor: (String, Color) = {
            guard speaker.isEnabled || subwoofer.isEnabled else { return ("Off", .secondary) }
            switch engine.status {
            case .idle: return ("Idle", .secondary)
            case .waitingForController: return ("Waiting for USB", .orange)
            case .running: return ("Playing", .green)
            case .permissionRequired: return ("Permission needed", .orange)
            case .failed: return ("Error", .red)
            }
        }()

        return HStack(spacing: 5) {
            Circle().fill(descriptor.1).frame(width: 7, height: 7)
            Text(descriptor.0)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(descriptor.1)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusCallout: some View {
        switch engine.status {
        case .waitingForController:
            callout(
                title: controllerState.connectionType == .bluetooth
                    ? "Connected over Bluetooth"
                    : "No controller sound device",
                icon: "cable.connector",
                message: "Plug the controller in with a USB cable. Playback starts on its own as soon as macOS sees it."
            ) { EmptyView() }

        case .permissionRequired:
            callout(
                title: "System Audio Recording Required",
                icon: "waveform.circle.fill",
                message: "Single Sense needs to read the system audio to send it to the controller. Nothing is recorded or saved. In System Settings, go to Privacy & Security → System Audio Recording Only and turn on Single Sense."
            ) {
                HStack(spacing: 10) {
                    Button("Try Again") { engine.retry() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") { engine.openPrivacySettings() }
                }
                .controlSize(.small)
            }

        case .failed(let message):
            callout(title: "Couldn't start", icon: "exclamationmark.triangle.fill", message: message) {
                Button("Try Again") { engine.retry() }
                    .controlSize(.small)
            }

        case .idle, .running:
            EmptyView()
        }
    }

    private func callout<Actions: View>(
        title: String,
        icon: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Volume")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(Int((speaker.volume * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                Slider(
                    value: Binding(
                        get: { manager.speakerConfig.volume },
                        set: { newValue in
                            manager.speakerConfig.volume = newValue
                            ControllerSpeakerEngine.shared.setGain(manager.speakerConfig.gain)
                        }
                    ),
                    in: 0...1
                )
                .accessibilityLabel("Controller speaker volume")
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
            }

            Text("Works on top of the Mac's own volume. The controller's speaker is small, so very loud, bass-heavy material may rattle.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Output

    private var outputSection: some View {
        let headphones = controllerState.headphonesConnected
        return VStack(alignment: .leading, spacing: 10) {
            Text("Output")
                .font(.headline.weight(.bold))

            HStack(spacing: 10) {
                Image(systemName: headphones ? "headphones" : "hifispeaker.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headphones ? "Headphone jack, stereo" : "Built-in speaker, mono")
                        .font(.subheadline.weight(.semibold))
                    if let name = engine.deviceName, engine.status.isRunning {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text("Plug headphones into the controller and the sound moves to them in stereo; unplug them and it returns to the speaker.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Subwoofer

    private func subwooferBinding<Value>(_ keyPath: WritableKeyPath<SubwooferConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { manager.subwooferConfig[keyPath: keyPath] },
            set: { newValue in
                manager.subwooferConfig[keyPath: keyPath] = newValue
                manager.applySpeakerConfiguration()
            }
        )
    }

    private var subwooferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: subwooferBinding(\.isEnabled)) {
                Text("Use the Grips as a Subwoofer")
                    .font(.headline.weight(.bold))
            }
            .toggleStyle(.switch)

            Text(speaker.isEnabled
                 ? "A 2.1 pair in your hands: the speaker plays everything above the crossover, the voice coils in the grips play everything below it."
                 : "Your Mac keeps playing as usual and the voice coils in the grips add the bass underneath — the actual bass line at the music's own level, not a vibration pattern.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if subwoofer.isEnabled, !coils.status.canPlay {
                Label("Needs the USB cable: over Bluetooth the grips can't be reached as a sound device.",
                      systemImage: "cable.connector")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                labelledSlider(
                    "Level",
                    value: subwooferBinding(\.level),
                    range: 0...1,
                    readout: "\(Int((subwoofer.level * 100).rounded()))%"
                )
                labelledSlider(
                    "Crossover",
                    value: subwooferBinding(\.crossoverHz),
                    range: SubwooferConfiguration.crossoverRange,
                    step: 5,
                    readout: "\(Int(subwoofer.crossoverHz)) Hz"
                )
                Text("Lower keeps the grips to the deepest notes; higher lets kick drums and bass guitar through too.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: subwooferBinding(\.boostDeepBass)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Boost deep bass")
                            .font(.callout.weight(.medium))
                        Text("The coils barely move below about 50 Hz, so the deepest notes get their octave added — still the same note, now something you can feel.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)

                Label("While this is on, Music Sync's rumble steps aside. The bass reaches the grips about 20 ms after the Mac's speakers.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!subwoofer.isEnabled)
            .opacity(subwoofer.isEnabled ? 1 : 0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func labelledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        readout: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.medium))
                .frame(width: 80, alignment: .leading)
            if let step {
                Slider(value: value, in: range, step: step)
                    .accessibilityLabel("Subwoofer \(title.lowercased())")
            } else {
                Slider(value: value, in: range)
                    .accessibilityLabel("Subwoofer \(title.lowercased())")
            }
            Text(readout)
                .font(.callout.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
