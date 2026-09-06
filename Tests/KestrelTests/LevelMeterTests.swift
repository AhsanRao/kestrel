import XCTest
@testable import Kestrel

/// The panel's waveform is driven by this, so it has to behave like a level meter and not like a
/// raw number: quick to rise, slow to fall, and never stuck.
final class LevelMeterTests: XCTestCase {
    func testSilenceReadsAsZero() {
        XCTAssertEqual(LevelMeter.normalise(rms: 0), 0)
        XCTAssertEqual(LevelMeter.normalise(rms: 0.0001), 0, accuracy: 0.001)
    }

    func testLoudSpeechReachesFullScale() {
        XCTAssertEqual(LevelMeter.normalise(rms: 0.6), 1, accuracy: 0.001)
    }

    func testOrdinarySpeechSitsInTheMiddleOfTheRange() {
        // A linear meter would put this near the bottom; a decibel scale should not.
        let level = LevelMeter.normalise(rms: 0.05)
        XCTAssertGreaterThan(level, 0.2)
        XCTAssertLessThan(level, 0.9)
    }

    func testTheMeterRisesFasterThanItFalls() {
        var rising = LevelMeter()
        var falling = LevelMeter()
        _ = rising.push(rms: 0.5)
        for _ in 0..<3 { _ = falling.push(rms: 0.5) }
        let afterOneLoudBuffer = rising.level

        _ = falling.push(rms: 0)
        let dropInOneBuffer = 1 - (falling.level / 1)
        XCTAssertGreaterThan(afterOneLoudBuffer, dropInOneBuffer,
                             "a sudden word should register faster than a pause clears")
    }

    func testTheLevelStaysWithinRange() {
        var meter = LevelMeter()
        for rms in [Float(0), 1, 10, -1, 0.3] {
            let level = meter.push(rms: rms)
            XCTAssertGreaterThanOrEqual(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
        }
    }

    func testAnEmptyBufferDecaysRatherThanFreezing() {
        var meter = LevelMeter()
        for _ in 0..<5 { _ = meter.push(rms: 0.5) }
        let before = meter.level
        let empty = [Float]()
        empty.withUnsafeBufferPointer { _ = meter.push($0) }
        XCTAssertLessThan(meter.level, before)
    }

    func testItSettlesToSilenceEventually() {
        var meter = LevelMeter()
        _ = meter.push(rms: 0.5)
        for _ in 0..<200 { _ = meter.decay() }
        XCTAssertEqual(meter.level, 0, accuracy: 0.01)
    }

    func testResetClearsIt() {
        var meter = LevelMeter()
        _ = meter.push(rms: 0.5)
        meter.reset()
        XCTAssertEqual(meter.level, 0)
    }

    func testRealSamplesProduceALevel() {
        var meter = LevelMeter()
        // A quarter-amplitude tone.
        let samples = (0..<1024).map { Float(sin(Double($0) * 0.1)) * 0.25 }
        samples.withUnsafeBufferPointer { _ = meter.push($0) }
        XCTAssertGreaterThan(meter.level, 0)
    }
}
