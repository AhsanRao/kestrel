import Foundation

/// Turns raw samples into something worth drawing.
///
/// A bare RMS reading jitters far too fast to read and sits in the bottom tenth of its range for
/// ordinary speech. This maps it onto a decibel scale, then smooths it with a fast attack and a
/// slow release — the shape every level meter uses, because it is the shape that looks like a
/// voice rather than like noise.
struct LevelMeter {
    /// Below this the room is silent; above it the meter is at full scale.
    static let floorDecibels: Float = -52
    static let ceilingDecibels: Float = -8

    /// Rise quickly so a sudden word registers; fall slowly so the meter does not flicker.
    var attack: Float = 0.55
    var release: Float = 0.12

    private(set) var level: Float = 0

    /// Feeds one buffer and returns the new smoothed level, 0…1.
    @discardableResult
    mutating func push(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return decay() }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return push(rms: (sum / Float(samples.count)).squareRoot())
    }

    @discardableResult
    mutating func push(rms: Float) -> Float {
        let target = LevelMeter.normalise(rms: rms)
        let rate = target > level ? attack : release
        level += (target - level) * rate
        level = min(max(level, 0), 1)
        return level
    }

    /// No audio arriving: sink back towards silence rather than freezing mid-reading.
    @discardableResult
    mutating func decay() -> Float {
        level = max(0, level - release * level)
        return level
    }

    mutating func reset() {
        level = 0
    }

    /// RMS → 0…1 on a decibel scale, because loudness is logarithmic and a linear meter spends
    /// its whole range on the loudest tenth of speech.
    static func normalise(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        guard decibels.isFinite else { return 0 }
        let span = ceilingDecibels - floorDecibels
        return min(max((decibels - floorDecibels) / span, 0), 1)
    }
}
