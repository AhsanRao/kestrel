import AppKit

// LSUIElement in Info.plist already hides the Dock icon; setting the policy explicitly keeps
// `swift run` (which has no bundle) behaving the same way.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let delegate = AppDelegate()
application.delegate = delegate
application.run()
