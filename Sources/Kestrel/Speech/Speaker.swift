import Foundation

/// What `SessionCoordinator` needs from anything that reads an answer out loud, so the engine
/// behind it can change without the pipeline noticing (spec §8.9).
///
/// Two implementations: `SystemSpeaker`, Apple's `AVSpeechSynthesizer`, and `KokoroSpeaker`, a
/// local neural model run as a subprocess.
protocol Speaker: AnyObject {
    /// True while audio is actually playing, so the coordinator can hold the panel open.
    var isSpeaking: Bool { get }

    /// Called on the main thread when the queue drains.
    var onFinish: (() -> Void)? { get set }

    /// Replaces anything being said. False when nothing was spoken.
    @discardableResult func speak(_ text: String, config: Config) -> Bool

    /// Adds to what is already queued, so an answer arriving sentence by sentence is read as one
    /// continuous reply rather than restarting on every fragment.
    @discardableResult func enqueue(_ text: String, config: Config) -> Bool

    func stop()
}
