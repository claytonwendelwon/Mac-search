import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var panel: SearchPanel?
    private let engine = SearchEngine()

    private let panelWidth: CGFloat = 720
    private let panelHeight: CGFloat = 480

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        setupHotKey()
        // Reveal on first launch so it's obvious the app started.
        showPanel()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass",
                                   accessibilityDescription: "Beacon Search")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Beacon  (⌥Space)",
                     action: #selector(showPanelFromMenu),
                     keyEquivalent: "")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Beacon",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanelFromMenu() {
        showPanel()
    }

    // MARK: - Panel

    private func setupPanel() {
        let panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        let root = SearchView(engine: engine, onClose: { [weak self] in
            self?.hidePanel()
        })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
        self.panel = panel
    }

    @objc func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        panel.positionOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        engine.focusRequestToken &+= 1 // nudge the text field to grab focus
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    // MARK: - Hotkey

    private func setupHotKey() {
        // Option + Space (avoids clashing with Spotlight's Cmd+Space).
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.togglePanel()
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    // Dismiss when the user clicks away / switches apps.
    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }
}
