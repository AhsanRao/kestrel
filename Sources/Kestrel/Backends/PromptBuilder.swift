import Foundation

/// Assembles the single prompt string handed to a CLI. Framing text lives in `Resources/Prompts`
/// so it can be edited without a rebuild (spec §9).
enum PromptBuilder {
    /// The core framing, plus only the blocks this question actually needs. The draft rules are a
    /// quarter of the whole thing and apply to a small fraction of questions; the browser note
    /// applies only when macOS handed over nothing but chrome.
    static func framing(for query: Query) -> String {
        var parts = [BundleResources.prompt(.ask)]
        if query.wantsDraft { parts.append(BundleResources.prompt(.askDraft)) }
        if query.screenText?.isEmpty ?? true { parts.append(BundleResources.prompt(.askBrowser)) }
        if query.tools {
            parts.append(BundleResources.prompt(.askTools)
                .replacingOccurrences(of: "{steps}", with: String(query.maximumSteps)))
        }
        return parts.joined(separator: "\n\n")
    }

    /// - Parameter mentionScreenshotPath: Claude reads the PNG itself via its Read tool, so it
    ///   needs the path in the prompt. Codex receives the image as an `--image` attachment.
    static func build(_ query: Query, mentionScreenshotPath: Bool = true) -> String {
        switch query.mode {
        case .dictationCleanup:
            return BundleResources.prompt(.dictationCleanup) + "\n" + query.text

        case .ask:
            var parts: [String] = []
            parts.append(framing(for: query))
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
            // Controls and content in one numbered list: an answer about a page's layout has to be
            // able to name the card it means, and a card is not a button.
            if !query.targets.isEmpty {
                let controls = query.targets.filter { $0.kind == .control }
                let regions = query.targets.filter { $0.kind == .region }
                if !controls.isEmpty {
                    parts.append("Things you can click:\n"
                                 + controls.map(\.listing).joined(separator: "\n"))
                }
                if !regions.isEmpty {
                    parts.append("Sections and content on screen:\n"
                                 + regions.map(\.listing).joined(separator: "\n"))
                }
            }
            if let where_ = query.location { parts.append(where_) }
            if let screenText = query.screenText, !screenText.isEmpty {
                parts.append("What the screen says right now:\n\(screenText)")
            }
            if let skills = query.skills, !skills.isEmpty {
                parts.append("Things to keep in mind here:\n\(skills)")
            }
            if let desktop = query.desktop, !desktop.isEmpty { parts.append(desktop) }
            if let brief = Conversation.brief(query.history) { parts.append(brief) }
            if let done = query.alreadyDone { parts.append("Already done by Kestrel, before you: \(done) Carry on from there; do not do it again.") }
            parts.append("Question: \(query.text)")
            return parts.joined(separator: "\n\n")
        }
    }
}
