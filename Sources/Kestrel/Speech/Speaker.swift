import Foundation

/// A voice engine: `SystemSpeaker` or `KokoroSpeaker` (spec §8.9).
protocol Speaker: AnyObject {
    /// True while audio is playing, so the panel stays open.
    var isSpeaking: Bool { get }

    /// Main thread, when the queue drains.
    var onFinish: (() -> Void)? { get set }

    /// Replaces anything being said. False when nothing was spoken.
    @discardableResult func speak(_ text: String, config: Config) -> Bool

    /// Appends, so a streamed answer reads as one reply instead of restarting per fragment.
    @discardableResult func enqueue(_ text: String, config: Config) -> Bool

    func stop()
}
