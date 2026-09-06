import Foundation

/// Swappable speech-to-text. Only a local implementation ships: audio never leaves the Mac.
protocol Transcriber: AnyObject {
    /// Blocking. Returns the cleaned transcript, or throws `KestrelError`.
    func transcribe(_ wav: URL, config: Config) throws -> String
    func cancel()
}
