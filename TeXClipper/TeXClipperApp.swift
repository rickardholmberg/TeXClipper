import SwiftUI

@main
struct TeXClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            ContentView(shortcutManager: appDelegate.shortcutManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var shortcutManager: ShortcutManager?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutManager = ShortcutManager()
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "function", accessibilityDescription: "TeXClipper")
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // Use Cmd+, to open settings (standard macOS shortcut)
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for comma with Command
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x2B, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x2B, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
