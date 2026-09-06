import AVFoundation
import XCTest
@testable import Kestrel

/// The cues are synthesised, so their shape is code and can be checked. A click at the start or
/// end of a tone is the classic bug here, and it is entirely an envelope problem.
final class SoundBoardTests: XCTestCase {
    func testEveryCueRendersSomething() {
        for cue in SoundBoard.Cue.allCases {
            XCTAssertFalse(SoundBoard.render(cue).isEmpty, "\(cue) rendered silence")
        }
    }

    func testCuesAreShortEnoughToBeCues() {
        for cue in SoundBoard.Cue.allCases {
            let seconds = Double(SoundBoard.render(cue).count) / SoundBoard.sampleRate
            XCTAssertLessThan(seconds, 0.2, "\(cue) is \(seconds)s — too long to be a cue")
            XCTAssertGreaterThan(seconds, 0.02, "\(cue) is too short to be heard")
        }
    }

    func testCuesAreQuiet() {
        for cue in SoundBoard.Cue.allCases {
            let peak = SoundBoard.render(cue).map(abs).max() ?? 0
            XCTAssertLessThanOrEqual(peak, 0.2, "\(cue) peaks at \(peak)")
            XCTAssertGreaterThan(peak, 0.02)
        }
    }

    func testTonesFadeInAndOutSoTheyDoNotClick() {
        let samples = SoundBoard.tone(frequency: 880, duration: 0.08, level: 0.2)
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.02)
        let middle = abs(samples[samples.count / 2])
        XCTAssertGreaterThan(middle, 0.02, "the middle of the tone should be at full level")
    }

    func testAZeroLengthToneIsEmptyRatherThanACrash() {
        XCTAssertTrue(SoundBoard.tone(frequency: 440, duration: 0, level: 0.2).isEmpty)
        XCTAssertTrue(SoundBoard.tone(frequency: 440, duration: -1, level: 0.2).isEmpty)
    }

    func testProgressCuesRiseAndFailureFalls() {
        XCTAssertEqual(SoundBoard.Cue.listening.tones, [660, 880])
        XCTAssertEqual(SoundBoard.Cue.answered.tones.first! < SoundBoard.Cue.answered.tones.last!, true)
        XCTAssertEqual(SoundBoard.Cue.failed.tones.first! > SoundBoard.Cue.failed.tones.last!, true)
    }

    func testEachCueSoundsDifferent() {
        let signatures = Set(SoundBoard.Cue.allCases.map { "\($0.tones)|\($0.toneDuration)" })
        XCTAssertEqual(signatures.count, SoundBoard.Cue.allCases.count)
    }

    // MARK: - When they play

    func testSoundsCanBeTurnedOff() {
        var config = Config.defaults
        XCTAssertTrue(SoundBoard.shouldPlay(config: config, muted: false))
        config.sounds = false
        XCTAssertFalse(SoundBoard.shouldPlay(config: config, muted: false))
    }

    func testAMutedMacStaysSilent() {
        XCTAssertFalse(SoundBoard.shouldPlay(config: .defaults, muted: true))
    }
}
