import Foundation
import ServiceManagement
import os

/// `SMAppService` login item (spec §10). No-ops when running outside an .app bundle, which is what
/// `swift run` does during development.
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func sync(with desired: Bool) {
        guard Bundle.main.bundleIdentifier != nil, isEnabled != desired else { return }
        do {
            if desired {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch at login \(desired ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
