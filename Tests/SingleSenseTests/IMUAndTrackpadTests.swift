import XCTest
@testable import SingleSense

/// Gyroscope and accelerometer, read from the HID input report with the
/// controller's own factory calibration.
final class IMUCalibrationTests: XCTestCase {

    /// A plausible feature report 0x05, byte 0 being the report ID.
    private func calibrationReport(
        gyroPlus: Int16 = 8000, gyroMinus: Int16 = -8000,
        speed: Int16 = 1000, accPlus: Int16 = 8192, accMinus: Int16 = -8192
    ) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: DualSenseProtocol.featureReportCalibrationSize)
        buffer[0] = DualSenseProtocol.featureReportCalibration
        func put(_ offset: Int, _ value: Int16) {
            buffer[offset] = UInt8(truncatingIfNeeded: value)
            buffer[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        }
        for (index, offset) in [7, 11, 15].enumerated() {
            _ = index
            put(offset, gyroPlus)
            put(offset + 2, gyroMinus)
        }
        put(19, speed); put(21, speed)
        put(23, accPlus); put(25, accMinus)
        put(27, accPlus); put(29, accMinus)
        put(31, accPlus); put(33, accMinus)
        return buffer
    }

    func testGyroScalesToDegreesPerSecond() throws {
        let calibration = try XCTUnwrap(DSIMUCalibration.parse(featureReport: calibrationReport()))
        let degrees = Float(calibration.gyro[0].apply(8000))
            / DualSenseProtocol.gyroResolutionPerDegPerSec
        XCTAssertEqual(degrees, 1000, accuracy: 1)
        XCTAssertEqual(calibration.gyro[0].apply(0), 0, "must read zero at rest")
        XCTAssertEqual(calibration.gyro[0].apply(-8000), -calibration.gyro[0].apply(8000))
    }

    func testAccelerometerScalesToG() throws {
        let calibration = try XCTUnwrap(DSIMUCalibration.parse(featureReport: calibrationReport()))
        let g = Float(calibration.accel[2].apply(8192)) / DualSenseProtocol.accelResolutionPerG
        XCTAssertEqual(g, 1.0, accuracy: 0.01)
        XCTAssertEqual(calibration.accel[2].apply(0), 0)
    }

    /// The reported symptom was the gyro mirroring the accelerometer. They
    /// come from different report offsets and must move independently.
    func testGyroAndAccelerometerAreIndependent() throws {
        let calibration = try XCTUnwrap(DSIMUCalibration.parse(featureReport: calibrationReport()))
        let base = DSInputLayout.payloadOffset(isBluetooth: true)
        var report = [UInt8](repeating: 0, count: DualSenseProtocol.inputReportSizeBT)
        report[0] = DualSenseProtocol.inputReportIDBT

        func put(_ offset: Int, _ value: Int16) {
            report[offset] = UInt8(truncatingIfNeeded: value)
            report[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        }
        func axis(_ offset: Int, _ index: Int) -> Int {
            Int(Int16(bitPattern: UInt16(report[offset + index * 2])
                | (UInt16(report[offset + index * 2 + 1]) << 8)))
        }
        let gyro = base + DSInputLayout.gyro
        let accel = base + DSInputLayout.accel

        // Lying still and flat: gravity on Z, no rotation anywhere.
        put(accel + 4, 8192)
        for i in 0..<3 { XCTAssertEqual(calibration.gyro[i].apply(axis(gyro, i)), 0) }
        XCTAssertEqual(Float(calibration.accel[2].apply(axis(accel, 2)))
                       / DualSenseProtocol.accelResolutionPerG, 1.0, accuracy: 0.01)

        // Rotating in place: the gyro responds, the accelerometer does not.
        put(gyro + 2, 4000)
        XCTAssertNotEqual(calibration.gyro[1].apply(axis(gyro, 1)), 0)
        XCTAssertEqual(calibration.gyro[0].apply(axis(gyro, 0)), 0)
        XCTAssertEqual(calibration.accel[0].apply(axis(accel, 0)), 0)
        XCTAssertEqual(calibration.accel[1].apply(axis(accel, 1)), 0)
    }

    func testSensorBlocksDoNotOverlap() {
        XCTAssertLessThanOrEqual(DSInputLayout.gyro + 6, DSInputLayout.accel)
        XCTAssertLessThanOrEqual(DSInputLayout.accel + 6, DSInputLayout.sensorTimestamp)
    }

    /// Clones and broken devices report unusable calibration; that must not
    /// divide by zero.
    func testUnusableCalibrationFallsBack() throws {
        var empty = [UInt8](repeating: 0, count: DualSenseProtocol.featureReportCalibrationSize)
        empty[0] = DualSenseProtocol.featureReportCalibration
        let calibration = try XCTUnwrap(DSIMUCalibration.parse(featureReport: empty))
        XCTAssertNotEqual(calibration.gyro[0].apply(1000), 0)
        XCTAssertNotEqual(calibration.accel[0].apply(1000), 0)
    }

    func testTruncatedReportIsRejected() {
        XCTAssertNil(DSIMUCalibration.parse(featureReport: [0x05, 0x00]))
    }
}

/// The DualSense touchpad driving the macOS cursor.
final class TrackpadGestureTests: XCTestCase {

    private func oneFinger(_ x: Float, _ y: Float, at time: TimeInterval, button: Bool = false) -> TrackpadSample {
        TrackpadSample(primaryActive: true, primaryX: x, primaryY: y, buttonDown: button, time: time)
    }
    private func twoFingers(_ x: Float, _ y: Float, at time: TimeInterval) -> TrackpadSample {
        TrackpadSample(primaryActive: true, primaryX: x, primaryY: y,
                       secondaryActive: true, secondaryX: x + 0.1, secondaryY: y, time: time)
    }
    private func lift(at time: TimeInterval) -> TrackpadSample { TrackpadSample(time: time) }

    private func moves(_ actions: [TrackpadAction]) -> [(dx: Double, dy: Double)] {
        actions.compactMap { if case .move(let dx, let dy) = $0 { return (dx, dy) }; return nil }
    }
    private func scrolls(_ actions: [TrackpadAction]) -> [(dx: Double, dy: Double)] {
        actions.compactMap { if case .scroll(let dx, let dy) = $0 { return (dx, dy) }; return nil }
    }

    func testPointerNeedsAReferenceBeforeItMoves() {
        var recognizer = TrackpadGestureRecognizer()
        XCTAssertTrue(moves(recognizer.process(oneFinger(0.5, 0.5, at: 0))).isEmpty)
        let moved = moves(recognizer.process(oneFinger(0.6, 0.5, at: 0.01)))
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved[0].dx, 0.1 * recognizer.sensitivity, accuracy: 1)
    }

    func testJitterAndTeleportsAreIgnored() {
        var recognizer = TrackpadGestureRecognizer()
        _ = recognizer.process(oneFinger(0.5, 0.5, at: 0))
        let jitter = TrackpadGestureRecognizer.jitter / 2
        XCTAssertTrue(moves(recognizer.process(oneFinger(0.5 + jitter, 0.5, at: 0.01))).isEmpty)

        recognizer.reset()
        _ = recognizer.process(oneFinger(0.1, 0.1, at: 0))
        XCTAssertTrue(moves(recognizer.process(oneFinger(0.9, 0.9, at: 0.01))).isEmpty,
                      "a finger relanding elsewhere must not fling the pointer")
    }

    func testShortStillContactIsATap() {
        var recognizer = TrackpadGestureRecognizer()
        _ = recognizer.process(oneFinger(0.5, 0.5, at: 0))
        _ = recognizer.process(oneFinger(0.501, 0.5, at: 0.05))
        XCTAssertEqual(recognizer.process(lift(at: 0.10)),
                       [.button(down: true, right: false), .button(down: false, right: false)])
    }

    func testDraggingAndLongContactsAreNotTaps() {
        var recognizer = TrackpadGestureRecognizer()
        _ = recognizer.process(oneFinger(0.2, 0.5, at: 0))
        _ = recognizer.process(oneFinger(0.8, 0.5, at: 0.05))
        XCTAssertTrue(recognizer.process(lift(at: 0.10)).isEmpty)

        recognizer.reset()
        _ = recognizer.process(oneFinger(0.5, 0.5, at: 0))
        XCTAssertTrue(recognizer.process(lift(at: 0.9)).isEmpty)
    }

    func testTwoFingerTapIsASecondaryClick() {
        var recognizer = TrackpadGestureRecognizer()
        _ = recognizer.process(twoFingers(0.4, 0.5, at: 0))
        XCTAssertEqual(recognizer.process(lift(at: 0.10)),
                       [.button(down: true, right: true), .button(down: false, right: true)])
    }

    func testTapToClickCanBeDisabled() {
        var recognizer = TrackpadGestureRecognizer()
        recognizer.tapToClick = false
        _ = recognizer.process(oneFinger(0.5, 0.5, at: 0))
        XCTAssertTrue(recognizer.process(lift(at: 0.05)).isEmpty)
    }

    func testTwoFingersScrollInsteadOfMoving() {
        var recognizer = TrackpadGestureRecognizer()
        _ = recognizer.process(twoFingers(0.5, 0.5, at: 0))
        let actions = recognizer.process(twoFingers(0.5, 0.6, at: 0.01))
        XCTAssertEqual(scrolls(actions).count, 1)
        XCTAssertTrue(moves(actions).isEmpty)
        XCTAssertLessThan(scrolls(actions)[0].dy, 0, "natural scrolling follows the finger")

        recognizer.reset()
        recognizer.naturalScrolling = false
        _ = recognizer.process(twoFingers(0.5, 0.5, at: 0))
        XCTAssertGreaterThan(scrolls(recognizer.process(twoFingers(0.5, 0.6, at: 0.01)))[0].dy, 0)
    }

    func testPhysicalClickAndDrag() {
        var recognizer = TrackpadGestureRecognizer()
        XCTAssertTrue(recognizer.process(oneFinger(0.5, 0.5, at: 0, button: true))
            .contains(.button(down: true, right: false)))

        let dragging = recognizer.process(oneFinger(0.6, 0.5, at: 0.01, button: true))
        XCTAssertTrue(dragging.contains { if case .drag = $0 { return true }; return false })

        XCTAssertTrue(recognizer.process(oneFinger(0.6, 0.5, at: 0.02, button: false))
            .contains(.button(down: false, right: false)))
    }

    func testTwoFingersOnAPhysicalClickMeansRightClick() {
        var recognizer = TrackpadGestureRecognizer()
        let sample = TrackpadSample(primaryActive: true, primaryX: 0.4, primaryY: 0.5,
                                    secondaryActive: true, secondaryX: 0.6, secondaryY: 0.5,
                                    buttonDown: true, time: 0)
        XCTAssertTrue(recognizer.process(sample).contains(.button(down: true, right: true)))
    }

    func testContactCountTracksFingers() {
        var recognizer = TrackpadGestureRecognizer()
        _ = recognizer.process(oneFinger(0.5, 0.5, at: 0))
        XCTAssertEqual(recognizer.contactCount, 1)
        _ = recognizer.process(twoFingers(0.5, 0.5, at: 0.01))
        XCTAssertEqual(recognizer.contactCount, 2)
        _ = recognizer.process(lift(at: 0.02))
        XCTAssertEqual(recognizer.contactCount, 0)
    }
}
