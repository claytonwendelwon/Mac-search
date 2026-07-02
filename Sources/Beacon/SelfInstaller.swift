import AppKit

/// Zero-friction install: when Beacon is launched from the DMG (or Downloads,
/// or a Gatekeeper translocation path) instead of an Applications folder, it
/// copies itself into /Applications, launches that copy, and quits. The user
/// just double-clicks the app in the disk image and ends up with an installed,
/// running Beacon - no dragging or hunting through folders required.
enum SelfInstaller {
    /// Returns true if an install was started and the current process is about
    /// to be replaced (the caller should stop launching).
    @discardableResult
    static func installIfNeeded() -> Bool {
        let bundlePath = Bundle.main.bundlePath

        // Only applies to real .app bundles (not bare debug executables).
        guard bundlePath.hasSuffix(".app") else { return false }
        // Already running from /Applications (or ~/Applications) - nothing to do.
        if bundlePath.contains("/Applications/") { return false }

        let destination = "/Applications/\((bundlePath as NSString).lastPathComponent)"
        let fm = FileManager.default
        Log.write("SelfInstaller: running from \(bundlePath), installing to \(destination)")

        // If an older copy is running from /Applications, ask it to quit so the
        // bundle can be replaced.
        let me = NSRunningApplication.current
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app != me {
            app.terminate()
        }

        do {
            if fm.fileExists(atPath: destination) {
                try fm.removeItem(atPath: destination)
            }
            try fm.copyItem(atPath: bundlePath, toPath: destination)
        } catch {
            // No write access or copy failure: just keep running from here
            // rather than blocking the user.
            Log.write("SelfInstaller: install failed (\(error.localizedDescription)); continuing in place")
            return false
        }

        // Relaunch from /Applications once this process has exited. The helper
        // shell outlives us, so there's no moment with two Beacons fighting
        // over the global hotkey.
        let script = "sleep 0.5; /usr/bin/open \"\(destination)\""
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", script]
        try? relauncher.run()

        Log.write("SelfInstaller: installed; relaunching from /Applications")
        NSApp.terminate(nil)
        return true
    }
}
