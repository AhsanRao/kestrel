import Foundation

/// Assembles the single prompt string handed to a CLI. Framing text lives in `Resources/Prompts`
/// so it can be edited without a rebuild (spec §9).
enum PromptBuilder {
    /// - Parameter mentionScreenshotPath: Claude reads the PNG itself via its Read tool, so it
    ///   needs the path in the prompt. Codex receives the image as an `--image` attachment.
    static func build(_ query: Query, mentionScreenshotPath: Bool = true) -> String {
        switch query.mode {
        case .dictationCleanup:
            return BundleResources.prompt(.dictationCleanup) + "\n" + query.text

        case .ask, .walkthrough:
            var parts: [String] = []
            parts.append(BundleResources.prompt(query.mode == .walkthrough ? .walkthrough : .ask))
            if mentionScreenshotPath {
                if let crop = query.focusCrop {
                    parts.append("The user circled a region of the screen. Read that crop first: \(crop.path)")
                    if let shot = query.screenshot {
                        parts.append("Full screen for context: \(shot.path)")
                    }
                } else if let shot = query.screenshot {
                    parts.append("Screenshot of the user's screen: \(shot.path)\nRead this file before answering.")
                }
            } else if query.focusCrop != nil {
                parts.append("The first attached image is the region the user circled; the second is the full screen.")
            }
            parts.append("Question: \(query.text)")
            return parts.joined(separator: "\n\n")
        }
    }
}
