import XCTest
@testable import SingleSense

/// The driver's outbound queue: ordered events, coalescing state, and never
/// more than one drain outstanding.
final class OutputQueueTests: XCTestCase {

    func testABurstSchedulesExactlyOneDrain() {
        var queue = DSOutputQueue()
        var schedules = 0
        for i in 0..<1000 where queue.enqueue(DSHardwareState.stub(tag: UInt8(i % 256))) {
            schedules += 1
        }
        XCTAssertEqual(schedules, 1, "a 60 Hz producer must not pile up work items")
        XCTAssertEqual(queue.coalescedStateUpdates, 999)
    }

    func testOnlyTheNewestStateIsDelivered() {
        var queue = DSOutputQueue()
        for i in 0..<50 { _ = queue.enqueue(DSHardwareState.stub(tag: UInt8(i))) }
        let batch = queue.takeWork()
        XCTAssertEqual(batch?.state?.playerLEDMask, 49)
        XCTAssertNil(queue.takeWork(), "queue should now be empty")
    }

    func testEventsAreNeverCoalescedAway() {
        var queue = DSOutputQueue()
        _ = queue.enqueue(DSOutputQueue.Event.ledReset)
        for i in 0..<20 { _ = queue.enqueue(DSHardwareState.stub(tag: UInt8(i))) }
        _ = queue.enqueue(DSOutputQueue.Event.ledReset)

        let batch = queue.takeWork()
        XCTAssertEqual(batch?.events, [.ledReset, .ledReset])
        XCTAssertNotNil(batch?.state)
    }

    /// A forced send exists to bypass the dedup filter; an ordinary update
    /// arriving behind it must not quietly cancel that.
    func testForcedSendSurvivesBeingSuperseded() {
        var queue = DSOutputQueue()
        _ = queue.enqueue(DSHardwareState.stub(tag: 1, forceSend: true))
        _ = queue.enqueue(DSHardwareState.stub(tag: 2, forceSend: false))
        let batch = queue.takeWork()
        XCTAssertEqual(batch?.state?.playerLEDMask, 2)
        XCTAssertEqual(batch?.state?.forceSend, true)
    }

    func testDrainIsReleasedWhenTheQueueRunsDry() {
        var queue = DSOutputQueue()
        XCTAssertTrue(queue.enqueue(DSHardwareState.stub()))
        XCTAssertFalse(queue.enqueue(DSHardwareState.stub()), "drain already claimed")
        _ = queue.takeWork()
        XCTAssertNil(queue.takeWork())
        XCTAssertTrue(queue.enqueue(DSHardwareState.stub()), "a new drain is needed")
    }

    func testRetryIsForcedAndCounted() {
        var queue = DSOutputQueue()
        _ = queue.enqueue(DSHardwareState.stub(tag: 7))
        let refused = queue.takeWork()!.state!
        queue.requeue(refused)
        let retry = queue.takeWork()?.state
        XCTAssertEqual(retry?.playerLEDMask, 7)
        XCTAssertEqual(retry?.forceSend, true, "the retry must bypass the dedup filter")
        XCTAssertEqual(retry?.attempts, 1)
    }

    func testANewerStateWinsOverARetry() {
        var queue = DSOutputQueue()
        _ = queue.enqueue(DSHardwareState.stub(tag: 1))
        let refused = queue.takeWork()!.state!
        _ = queue.enqueue(DSHardwareState.stub(tag: 2))
        queue.requeue(refused)
        XCTAssertEqual(queue.takeWork()?.state?.playerLEDMask, 2,
                       "stale retry must not overwrite fresher state")
    }

    func testClearDropsTheBacklog() {
        var queue = DSOutputQueue()
        _ = queue.enqueue(DSOutputQueue.Event.ledReset)
        _ = queue.enqueue(DSHardwareState.stub())
        queue.clear()
        XCTAssertNil(queue.takeWork(), "a vanished device must not replay work later")
        XCTAssertTrue(queue.enqueue(DSHardwareState.stub()))
    }
}

/// The audio analysis queue, exercised at the real producer/consumer rates.
final class AnalysisFrameQueueTests: XCTestCase {

    private let producerHz = 48_000.0 / 512.0   // ~93.75, one frame per hop
    private let consumerHz = 60.0

    func testNoBeatIsLostBetweenConsumerTicks() {
        var queue = AnalysisFrameQueue()
        var frameIndex = 0
        var beatsSent = 0
        var beatsSeen = 0
        var maxDepth = 0

        for tick in 0..<600 {                       // ten seconds
            let now = Double(tick) / consumerHz
            var batch: [AnalysisFrame] = []
            while Double(frameIndex) / producerHz <= now {
                let isBeat = frameIndex % 47 == 0   // roughly every half second
                if isBeat { beatsSent += 1 }
                batch.append(AnalysisFrame(
                    time: Double(frameIndex) / producerHz,
                    levels: .uniform(0.5, beat: isBeat ? 1 : 0)
                ))
                frameIndex += 1
            }
            queue.append(contentsOf: batch)
            maxDepth = max(maxDepth, queue.depth)
            if queue.drain(upTo: now).beat > 0.5 { beatsSeen += 1 }
        }

        XCTAssertEqual(beatsSeen, beatsSent, "a faster producer must not drop transients")
        XCTAssertLessThanOrEqual(maxDepth, 3, "the queue should stay shallow in steady state")
        XCTAssertEqual(queue.droppedFrames, 0)
    }

    func testFramesDrainInOrderAndFutureFramesStay() {
        var queue = AnalysisFrameQueue()
        for i in 0..<10 {
            queue.append(contentsOf: [AnalysisFrame(
                time: Double(i) * 0.01, levels: .uniform(Float(i) / 10)
            )])
        }
        let drained = queue.drain(upTo: 0.05)
        XCTAssertEqual(drained.overall, 0.5, accuracy: 0.001)
        XCTAssertEqual(queue.depth, 4, "frames not yet due must remain queued")
    }

    func testAStalledConsumerCostsLatencyNotMemory() {
        var queue = AnalysisFrameQueue()
        for i in 0..<500 {
            queue.append(contentsOf: [AnalysisFrame(
                time: Double(i) / producerHz, levels: .uniform(0.5)
            )])
        }
        XCTAssertEqual(queue.depth, AnalysisFrameQueue.capacity)
        XCTAssertEqual(queue.droppedFrames, 500 - AnalysisFrameQueue.capacity)
    }

    func testValueIsHeldThroughJitterThenFallsSilent() {
        var queue = AnalysisFrameQueue()
        queue.append(contentsOf: [AnalysisFrame(time: 0, levels: .uniform(1.0))])
        XCTAssertEqual(queue.drain(upTo: 0).overall, 1.0)

        // A brief gap holds the last reading rather than flickering.
        XCTAssertEqual(queue.drain(upTo: 0.1).overall, 1.0)

        // A stalled stream must not leave the lightbar and motors stuck on.
        XCTAssertEqual(queue.drain(upTo: 0.5), .silent)
    }

    func testResetClearsEverything() {
        var queue = AnalysisFrameQueue()
        queue.append(contentsOf: [AnalysisFrame(time: 0, levels: .uniform(1))])
        _ = queue.drain(upTo: 0)
        queue.reset()
        XCTAssertEqual(queue.depth, 0)
        XCTAssertEqual(queue.droppedFrames, 0)
        XCTAssertEqual(queue.drain(upTo: 1000), .silent)
    }
}
