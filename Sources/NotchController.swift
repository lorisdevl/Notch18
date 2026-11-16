import AppKit
import SwiftUI

/// Fenêtre transparente posée par-dessus l'encoche, au-dessus de la barre des menus.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Gère l'ouverture / fermeture de l'encoche au survol, au clic, au glisser-déposer et au clavier.
final class NotchController {
    static var shared: NotchController?

    let panel: NotchPanel
    private let state = NotchState.shared
    private var timer: Timer?
    private var hoverStart: Date?
    private var leaveStart: Date?
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var keyMonitor: Any?

    init(panel: NotchPanel) {
        self.panel = panel
        NotchController.shared = self
    }

    func start() {
        layout()
        panel.orderFrontRegardless()

        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.layout() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.panel.orderFrontRegardless()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            guard let self, self.state.isOpen, !self.state.pinned else { return }
            if !self.openRect().contains(NSEvent.mouseLocation) { self.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.state.isOpen {
                self.close()
                return nil
            }
            return event
        }
    }

    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    func layout() {
        guard let screen = Self.targetScreen() else { return }
        state.updateMetrics(for: screen)
        let size = state.panelSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func closedRect() -> NSRect {
        guard let f = Self.targetScreen()?.frame else { return .zero }
        let w = ClosedLayout.width() + 16
        let h = state.notchHeight + (state.sneak != nil ? 30 : 0) + 6
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h + 2)
    }

    private func openRect() -> NSRect {
        guard let f = Self.targetScreen()?.frame else { return .zero }
        let w = state.openSize.width + 30
        let h = state.openSize.height + 18
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h + 2)
    }

    private func setIgnoresMouse(_ value: Bool) {
        if panel.ignoresMouseEvents != value { panel.ignoresMouseEvents = value }
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let mouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        let dragCount = NSPasteboard(name: .drag).changeCount
        if !mouseDown { dragBaseline = dragCount }
        let draggingFile = mouseDown && dragCount != dragBaseline

        if state.isOpen {
            setIgnoresMouse(false)
            if openRect().contains(mouse) {
                leaveStart = nil
                state.stickyUntilHover = false
                return
            }
            // On ne ferme pas si épinglé, ouvert au clavier, ou si l'utilisateur est en train d'écrire.
            if state.pinned || state.stickyUntilHover || panel.isKeyWindow || mouseDown { return }
            if leaveStart == nil { leaveStart = Date() }
            if let start = leaveStart, Date().timeIntervalSince(start) > 0.3 { close() }
        } else {
            let inside = closedRect().contains(mouse)
            setIgnoresMouse(!inside)
            guard inside else { hoverStart = nil; return }
            if draggingFile { open(tab: .shelf); return }
            guard UserDefaults.standard.bool(forKey: "openOnHover"), !mouseDown else { return }
            if hoverStart == nil { hoverStart = Date() }
            if let start = hoverStart,
               Date().timeIntervalSince(start) >= UserDefaults.standard.double(forKey: "hoverDelay") {
                open()
            }
        }
    }

    func open(tab: NotchTab? = nil, sticky: Bool = false) {
        if let tab { state.tab = tab }
        hoverStart = nil
        leaveStart = nil
        guard !state.isOpen else { return }
        state.stickyUntilHover = sticky
        state.sneak = nil
        setIgnoresMouse(false)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { state.isOpen = true }
        if UserDefaults.standard.bool(forKey: "haptics") {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func close() {
        guard state.isOpen else { return }
        leaveStart = nil
        hoverStart = nil
        state.stickyUntilHover = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { state.isOpen = false }
        if panel.isKeyWindow {
            // Rend le clavier à l'app précédente.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func toggle() {
        if state.isOpen { close() } else { open(sticky: true) }
    }
}
