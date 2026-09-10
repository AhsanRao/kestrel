import AppKit

/// Opens the setup window, and optionally photographs it. `KESTREL_PREVIEW_ONBOARDING=download`
/// also starts the voice download — the only way to see the progress meter without pressing it —
/// and any step's name — `welcome`, `voice`, `permissions`, `profile`, `ready` — opens on it.
enum OnboardingPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_ONBOARDING"] != nil
    }

    @MainActor private static var window: OnboardingWindow?

    @MainActor
    static func run() {
        let onboarding = OnboardingWindow()
        onboarding.show()
        window = onboarding

        switch ProcessInfo.processInfo.environment["KESTREL_PREVIEW_ONBOARDING"] {
        case "download": onboarding.model.voiceDownloader.start()
        case let name?:
            if let step = OnboardingModel.Step.allCases.first(where: {
                "\($0)".caseInsensitiveCompare(name) == .orderedSame
            }) {
                onboarding.model.go(to: step)
            }
        default: break
        }

        PreviewCapture.shoot(after: PreviewCapture.delay(default: 3.0),
                             PreviewCapture.around(onboarding.window))
    }
}
