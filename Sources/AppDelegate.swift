import AppKit
import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let openSettings = Notification.Name("Notch18.openSettings")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let hotKey = HotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "openOnHover": true,
            "hoverDelay": 0.15,
            "showTrackSneak": true,
            "showBatterySneak": true,
            "clipboardEnabled": true,
            "weatherCity": "Nantes",
            "pingHost": "1.1.1.1",
            "pomoWork": 25,
            "pomoShort": 5,
            "pomoLong": 15,
            "pomoAuto": true,
            "showGardeInNotch": true,
            "mirrorFlip": true,
            "haptics": true,
            "lastCountdown": 300.0
        ])

        // Fenêtre de l'encoche
        let panel = NotchPanel()
        let host = FirstMouseHostingView(rootView: NotchRootView())
        host.sizingOptions = []
        panel.contentView = host
        controller = NotchController(panel: panel)
        controller.start()

        // Services
        MediaManager.shared.start()
        CalendarManager.shared.start()
        WeatherManager.shared.start()
        SystemMonitor.shared.start()
        ClipboardManager.shared.start()
        _ = GardeManager.shared
        _ = ShelfManager.shared
        _ = LauncherManager.shared

        setupStatusItem()

        HotKey.action = { [weak self] in self?.controller.toggle() }
        hotKey.register()

        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Notch18")
        }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Ouvrir l'encoche (⌥⌘N)", action: #selector(toggleNotch), keyEquivalent: "")
        let settings = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quitter Notch18", action: #selector(quitApp), keyEquivalent: "q")
        for item in [open, settings] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleNotch() { controller.toggle() }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Réglages de Notch18"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

/// Raccourci clavier global ⌥⌘N (API Carbon, ne demande aucune autorisation).
final class HotKey {
    static var action: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4E313831), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
