import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@main
enum Portly {
    static func main() {
        let args = CommandLine.arguments
        // `Portly --list` prints what the widget sees; `--kill <pid>` stops one server. Handy for scripts and debugging.
        if args.contains("--list") {
            for s in Scanner.scan() {
                let ports = s.ports.isEmpty ? "-" : s.ports.map(String.init).joined(separator: ",")
                print("\(s.id)\t\(ports)\t\(s.name)\t\(s.manager) \(s.script)\t\(s.directory)")
            }
            return
        }
        if let i = args.firstIndex(of: "--kill"), i + 1 < args.count, let pid = pid_t(args[i + 1]) {
            Scanner.kill(rootPid: pid)
            return
        }
        if args.contains("--toggle") {
            DistributedNotificationCenter.default().postNotificationName(AppDelegate.toggleNotification, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            return
        }
        // Before deleting the app: drop its login item so System Settings isn't left with a dangling entry.
        if args.contains("--remove-login-item") {
            try? SMAppService.mainApp.unregister()
            print("login item: \(SMAppService.mainApp.status == .enabled ? "still enabled" : "removed")")
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Posted by `Portly --toggle`, so the widget can be opened from scripts or other launchers.
    static let toggleNotification = Notification.Name("com.code7551.portly.toggle")

    private let store = Store()
    private var statusItem: NSStatusItem!
    private var panel: WidgetPanel!
    private var hotKey: HotKey?
    private var clickMonitor: Any?
    private var timer: Timer?
    private var lastClosed = Date.distantPast
    private let idleIcon = PortlyIcon.image(filled: false)
    private let runningIcon = PortlyIcon.image(filled: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = idleIcon
            button.setAccessibilityLabel("Portly")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }

        panel = WidgetPanel(rootView: WidgetView(store: store))
        panel.delegate = self
        panel.onResize = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.positionPanel(animated: true)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handleKey(event) ? nil : event
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(togglePanel),
                                                            name: Self.toggleNotification, object: nil,
                                                            suspensionBehavior: .deliverImmediately)

        store.onUpdate = { [weak self] servers in self?.updateStatusItem(servers) }
        store.refresh()
        store.ensureLaunchAtLogin()

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.store.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }
    }

    private func updateStatusItem(_ servers: [DevServer]) {
        guard let button = statusItem.button else { return }
        button.image = servers.isEmpty ? idleIcon : runningIcon
        button.title = servers.isEmpty ? "" : " \(servers.count)"
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.toolTip = servers.isEmpty
            ? "Portly — all ports quiet"
            : servers.map { "\($0.name)  \($0.ports.map { ":\($0)" }.joined(separator: " "))" }.joined(separator: "\n")
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else if Date().timeIntervalSince(lastClosed) > 0.25 {
            // The guard stops a click on the icon from reopening the panel it just closed by taking focus.
            showPanel()
        }
    }

    private func showPanel() {
        store.selection = 0
        store.reset()
        store.refresh()
        positionPanel()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastClosed = Date()
        statusItem.button?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    /// Hangs the panel just under the menu bar, centred on the icon. Uses the icon's x only, because with an
    /// auto-hiding menu bar the status item's window sits above the top of the screen until you reveal it.
    private func positionPanel(animated: Bool = false) {
        let size = panel.fittingContentSize
        let (screen, iconX) = iconAnchor()
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top,
                                statusItem.button?.window?.frame.height ?? 0, NSStatusBar.system.thickness)
        let top = screen.frame.maxY - menuBarHeight - 6
        let margin: CGFloat = 8
        let x = min(max(iconX - size.width / 2, screen.visibleFrame.minX + margin),
                    screen.visibleFrame.maxX - size.width - margin)
        let frame = NSRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
        guard animated else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            return
        }
        // Follows the page slide, so the panel grows/shrinks from its top edge instead of jumping.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    private func iconAnchor() -> (NSScreen, CGFloat) {
        if let frame = statusItem.button?.window?.frame {
            let candidates = NSScreen.screens.filter { $0.frame.minX <= frame.midX && frame.midX < $0.frame.maxX }
            if let screen = candidates.min(by: { abs($0.frame.maxY - frame.minY) < abs($1.frame.maxY - frame.minY) }) {
                return (screen, frame.midX)
            }
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        return (screen, screen.visibleFrame.maxX)
    }

    /// List: ↑/↓ select · ↩ / → open the server's page · ⌘R refresh · ⌘Q quit · esc close.
    /// Server page: ↩ web · F Finder · T terminal · esc / ← back. Confirmation: ↩ stop · esc cancel.
    /// Stopping deliberately has no shortcut — it's the Stop Server button, then a confirmation.
    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        let chars = event.charactersIgnoringModifiers ?? ""
        let key = Int(event.keyCode)
        let plain = mods.isEmpty
        let isReturn = plain && (key == kVK_Return || key == kVK_ANSI_KeypadEnter)

        if store.activeConfirm != nil {
            if plain && key == kVK_Escape { store.cancelConfirm() }
            else if isReturn { store.confirm() }
            else if mods.contains(.command) { return handleShortcut(mods, chars, event) }
            return true   // nothing else while a confirmation is up
        }
        if case .detail(let id) = store.page, let server = store.server(id) {
            if plain && (key == kVK_Escape || key == kVK_LeftArrow) { store.back() }
            else if isReturn { store.open(server) }
            else if plain && key == kVK_ANSI_F { store.reveal(server) }
            else if plain && key == kVK_ANSI_T { store.openTerminal(server) }
            else if mods.contains(.command) { return handleShortcut(mods, chars, event) }
            return true
        }
        return handleShortcut(mods, chars, event)
    }

    private func handleShortcut(_ mods: NSEvent.ModifierFlags, _ chars: String, _ event: NSEvent) -> Bool {
        switch (mods, Int(event.keyCode)) {
        case ([], kVK_UpArrow): store.moveSelection(-1)
        case ([], kVK_DownArrow): store.moveSelection(1)
        case ([], kVK_Return), ([], kVK_ANSI_KeypadEnter), ([], kVK_RightArrow): store.openDetailForSelected()
        case ([], kVK_Escape): closePanel()
        case ([.command], _) where chars == "r": store.refresh()
        case ([.command], _) where chars == "q": NSApp.terminate(nil)
        default: return false
        }
        return true
    }
}

/// System-wide hotkey via Carbon — no Accessibility permission needed.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false
    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        if !HotKey.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                DispatchQueue.main.async { HotKey.handlers[id.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.installed = true
        }
        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[id] = handler
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x4244_4256), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
