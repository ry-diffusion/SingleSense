import SwiftUI

public struct TrackpadView: View {
    @ObservedObject var trackpad = TrackpadService.shared
    @ObservedObject var controllerState = DualSenseManager.shared.controllerState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !trackpad.hasPermission { permissionCallout }
                settings
                livePad
                gestureReference
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cursorarrow.rays")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Touchpad as a Mac Trackpad")
                    .font(.title3.weight(.bold))
                Text("Drives the macOS cursor from the DualSense touchpad, reading the two contact points straight out of the HID input report.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $trackpad.isEnabled)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
                .disabled(!trackpad.hasPermission)
                .accessibilityLabel("Use touchpad as trackpad")
                .accessibilityHint("Lets the controller's touchpad move the Mac pointer")
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private var permissionCallout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Single Sense needs Accessibility permission to move the cursor and click.",
                  systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("macOS only lets an app post mouse events once it is trusted for Accessibility. Nothing else on this page works until then.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Grant Access") { trackpad.requestPermission() }
                    .buttonStyle(.borderedProminent)
                Button("Open Privacy Settings") { trackpad.openPrivacySettings() }
            }
            .controlSize(.small)

            Text("This page updates by itself once you allow it — no need to relaunch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tuning")
                .font(.headline.weight(.bold))

            slider("Pointer Speed", value: $trackpad.sensitivity, range: 400...3200, unit: "px")
            slider("Scroll Speed", value: $trackpad.scrollSensitivity, range: 200...2000, unit: "px")

            Divider()

            Toggle("Tap to click", isOn: $trackpad.tapToClick)
                .font(.callout)
            Toggle("Natural scrolling", isOn: $trackpad.naturalScrolling)
                .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.callout.monospaced().weight(.bold))
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) \(unit)")
        }
    }

    /// Live view of the two contact points, straight from the input report.
    private var livePad: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Contacts")
                    .font(.headline.weight(.bold))
                Spacer()
                Text(trackpad.contactCount == 0 ? "No contact" : "\(trackpad.contactCount) finger\(trackpad.contactCount > 1 ? "s" : "")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(trackpad.contactCount > 0 ? .green : .secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(controllerState.buttonTouchpad ? Color.accentColor : Color.secondary.opacity(0.25),
                                lineWidth: controllerState.buttonTouchpad ? 2 : 1)

                    if controllerState.touch1Active {
                        contactDot(geo: geo, x: controllerState.touch1X, y: controllerState.touch1Y, tint: .accentColor)
                    }
                    if controllerState.touch2Active {
                        contactDot(geo: geo, x: controllerState.touch2X, y: controllerState.touch2Y, tint: .orange)
                    }
                }
            }
            // The DualSense pad is 1920 x 1080 units, so match its shape.
            .aspectRatio(1920.0 / 1080.0, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Touchpad contacts")
            .accessibilityValue(
                trackpad.contactCount == 0
                    ? "No contact"
                    : "\(trackpad.contactCount) finger\(trackpad.contactCount > 1 ? "s" : "")"
                        + (controllerState.buttonTouchpad ? ", pressed" : "")
            )

            Text(controllerState.buttonTouchpad ? "Touchpad pressed" : "Press the pad to click")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func contactDot(geo: GeometryProxy, x: Float, y: Float, tint: Color) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 14, height: 14)
            .shadow(color: tint.opacity(0.7), radius: 5)
            .position(
                x: CGFloat(max(0, min(1, x))) * geo.size.width,
                y: CGFloat(max(0, min(1, y))) * geo.size.height
            )
    }

    private var gestureReference: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gestures")
                .font(.headline.weight(.bold))
            gestureRow("hand.point.up.left", "One finger", "Move the pointer")
            gestureRow("hand.tap", "One-finger tap", "Left click")
            gestureRow("hand.draw", "Two fingers", "Scroll")
            gestureRow("hand.tap.fill", "Two-finger tap", "Right click")
            gestureRow("rectangle.compress.vertical", "Press the pad", "Left click, or right click with two fingers down")
            gestureRow("arrow.up.and.down.and.arrow.left.and.right", "Press and drag", "Drag selection")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    private func gestureRow(_ icon: String, _ gesture: String, _ effect: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .accessibilityHidden(true)
                .font(.callout)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(gesture)
                .font(.callout.weight(.medium))
                .frame(width: 130, alignment: .leading)
            Text(effect)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gesture): \(effect)")
    }
}
