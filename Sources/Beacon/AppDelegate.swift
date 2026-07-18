import AppKit
import SwiftUI
import Carbon.HIToolbox
import Quartz
import QuartzCore
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var panel: SearchPanel?
    private let engine = SearchEngine()
    /// Sparkle auto-updater. Checks the appcast (SUFeedURL in Info.plist) on
    /// its default schedule and on demand from the status menu.
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private let panelWidth: CGFloat = 740
    private let panelHeight: CGFloat = 500
    private let refinementSidebarWidth: CGFloat = 156

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("Launching Beacon...")
        // Launched from the DMG or Downloads? Install into /Applications and
        // relaunch from there - the user never has to drag anything.
        if SelfInstaller.installIfNeeded() { return }
        setupStatusItem()
        setupPanel()
        setupHotKey()
        showPanel()
        // Instantiating the lazy controller starts Sparkle's scheduled checks.
        _ = updaterController
        // Background license re-check (no-op unless a key is stored and the
        // last check is >3 days old; failures just consume the grace window).
        LicenseStore.shared.revalidateIfNeeded()
        // Touch the Messages DB once so macOS registers Beacon in the Full Disk
        // Access list (users can then just flip the toggle, no manual add).
        engine.warmMessageAccess()
        // Begin recording clipboard history (text only, private/transient
        // copies excluded) so it's searchable under the Clipboard filter.
        ClipboardStore.shared.start()
        Log.write("Ready. Menu-bar icon active; panel shown.")
    }

    // MARK: - Menu bar

    /// Rebuilt on every open so the license line reflects current state.
    private var statusMenu: NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Beacon  (⌥S)",
                     action: #selector(showPanelFromMenu),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let checkForUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdates.target = updaterController
        menu.addItem(checkForUpdates)
        switch LicenseStore.shared.status {
        case .licensed, .grace:
            let licensed = NSMenuItem(title: "License: Active ✓",
                                      action: nil, keyEquivalent: "")
            licensed.isEnabled = false
            menu.addItem(licensed)
        case .unlicensed, .lapsed:
            menu.addItem(withTitle: "Enter License…",
                         action: #selector(promptForLicense),
                         keyEquivalent: "")
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Beacon",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func promptForLicense() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Enter your Beacon license key"
        alert.informativeText = "Your key is on the receipt page from your "
            + "purchase (it looks like BEACON-XXXXX-XXXXX-XXXXX)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "BEACON-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        LicenseStore.shared.activate(key: field.stringValue) { result in
            let outcome = NSAlert()
            switch result {
            case .success:
                outcome.messageText = "Beacon is licensed — thank you!"
                outcome.informativeText = "Updates and future features are "
                    + "all included. Happy searching."
            case .failure(let error):
                outcome.messageText = "Couldn't activate that key"
                outcome.informativeText = error.localizedDescription
                outcome.alertStyle = .warning
            }
            outcome.runModal()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = BeaconMenuIcon.make()
            button.imagePosition = .imageOnly
            button.toolTip = "Beacon - click to search (⌥S)"
            // Left-click opens the search bar; right-click shows the menu.
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            guard let statusItem else { return }
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil) // open the menu
            statusItem.menu = nil                // detach so left-click works next time
        } else {
            togglePanel()
        }
    }

    @objc private func showPanelFromMenu() {
        showPanel()
    }

    // MARK: - Panel

    private func setupPanel() {
        let sidebarOpen = UserDefaults.standard.bool(forKey: "refinementSidebarOpen")
        let initialWidth = panelWidth + (sidebarOpen ? refinementSidebarWidth : 0)
        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: panelHeight)
        )
        let root = SearchView(
            engine: engine,
            onClose: { [weak self] in self?.hidePanel() },
            onEditingChanged: { [weak panel] editing in
                panel?.isMovableByWindowBackground = !editing
            },
            onRefinementSidebarChanged: { [weak self] open in
                self?.setRefinementSidebarOpen(open)
            }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 24
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.contentMinSize = NSSize(width: panelWidth, height: panelHeight)
        panel.contentMaxSize = NSSize(
            width: panelWidth + refinementSidebarWidth,
            height: panelHeight
        )
        panel.setContentSize(
            NSSize(width: initialWidth, height: panelHeight)
        )
        panel.delegate = self
        self.panel = panel
    }

    private func setRefinementSidebarOpen(_ open: Bool) {
        guard let panel else { return }
        let targetWidth = panelWidth + (open ? refinementSidebarWidth : 0)
        guard abs(panel.frame.width - targetWidth) > 1 else { return }
        var target = panel.frame
        target.size.width = targetWidth
        target.origin.x += open
            ? -refinementSidebarWidth
            : refinementSidebarWidth
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22, 1, 0.36, 1
            )
            panel.animator().setFrame(target, display: true)
        }
    }

    @objc func togglePanel() {
        Log.write("togglePanel (visible=\(panel?.isVisible ?? false))")
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        // Re-run the active query so the reopened panel is never stale.
        engine.refreshForPanelShow()
        panel.positionOnActiveScreen()
        // Pull the app forward (even from another app / full-screen space) and
        // make the panel key so the search field can show a blinking caret.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        // Nudge the text field to become first responder (caret on). Do it now
        // and again on the next runloop tick, since activation can be async.
        engine.focusRequestToken &+= 1
        DispatchQueue.main.async { [weak self] in
            self?.panel?.makeKey()
            self?.engine.focusRequestToken &+= 1
        }
    }

    private func hidePanel() {
        // Take any open Quick Look preview down with the panel so it can't
        // linger over other apps once the search UI is gone.
        if QLPreviewPanel.sharedPreviewPanelExists(),
           QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        }
        panel?.orderOut(nil)
    }

    // MARK: - Hotkey

    private func setupHotKey() {
        // Option + S. Avoids Cmd+S (Save) and Cmd+Space (Spotlight); as a
        // registered global hotkey it intercepts the keystroke system-wide
        // instead of typing into the focused app.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey)) { [weak self] in
            Log.write("Hotkey fired (Option+S).")
            self?.togglePanel()
        }
        if hotKey?.isRegistered == true {
            Log.write("Global hotkey Option+S registered OK.")
        } else {
            Log.write("Global hotkey NOT registered (status \(hotKey?.registrationStatus ?? -1)). Use the menu-bar icon.")
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    // Dismiss when the user clicks away / switches apps.
    func windowDidResignKey(_ notification: Notification) {
        // The new key window isn't set yet inside this notification, so decide
        // on the next runloop tick. Key moving to one of our own windows —
        // the Quick Look panel or an edit popover — must not dismiss the
        // search panel or cancel filter editing; only leaving the app should.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            if panel.isKeyWindow { return }
            if let keyWindow = NSApp.keyWindow {
                if keyWindow is QLPreviewPanel { return }
                var ancestor: NSWindow? = keyWindow
                while let current = ancestor {
                    if current === panel { return }
                    ancestor = current.parent
                }
            }
            if FilterLayoutStore.shared.isEditing {
                FilterLayoutStore.shared.cancelMove()
                FilterLayoutStore.shared.isEditing = false
                panel.isMovableByWindowBackground = true
            }
            // First launch must remain discoverable even if Finder or the DMG
            // takes focus during relaunch. Escape still closes it, and normal
            // click-away behavior begins after the welcome hint is dismissed.
            guard UserDefaults.standard.bool(forKey: "hasSeenWelcome") else { return }
            self.hidePanel()
        }
    }
}
