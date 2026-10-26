import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private var engine: ScrollEngine!
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch opens the existing instance rather than adding taps.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier:
            Bundle.main.bundleIdentifier ?? "local.smoothwheel.app")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        engine = ScrollEngine(preferences: preferences)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        engine.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusIcon() }
        }.store(in: &subscriptions)
        preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusIcon() }
        }.store(in: &subscriptions)
        updateStatusIcon()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || !engine.accessibilityGranted {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: engine.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: preferences.enabled ? "Приостановить сглаживание" : "Включить сглаживание",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let settings = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить SmoothWheel", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func updateStatusIcon() {
        let image = NSImage(systemSymbolName: engine.running ? "computermouse.fill" : "computermouse",
                            accessibilityDescription: "SmoothWheel")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "SmoothWheel — \(engine.statusText)"
    }

    @objc private func toggleEnabled() { preferences.enabled.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc private func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(preferences: preferences, engine: engine))
            let settings = NSWindow(contentViewController: controller)
            settings.title = "SmoothWheel"
            settings.styleMask = [.titled, .closable, .miniaturizable]
            settings.isReleasedWhenClosed = false
            settings.center()
            window = settings
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { engine?.stop() }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
