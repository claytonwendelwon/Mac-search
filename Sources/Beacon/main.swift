import AppKit

// Beacon is an accessory (menu-bar) app summoned by a global hotkey.
// We bootstrap NSApplication manually so we control the activation policy
// and lifecycle precisely (no Dock icon, no main window on launch).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
