import AppKit
import ServiceManagement
import SwiftUI

final class Store: ObservableObject {
    @Published private(set) var servers: [DevServer] = []
    @Published var selection = 0
    @Published private(set) var stopping: Set<pid_t> = []
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var page: Page = .list
    @Published private(set) var confirming: Confirm?

    enum Page: Hashable {
        case list
        case detail(pid_t)
    }

    enum Confirm: Hashable {
        case stop(pid_t)
        case stopAll
    }

    /// The pending confirmation — nil once what it's about has gone away.
    var activeConfirm: Confirm? {
        switch confirming {
        case .stop(let id)?: return server(id) == nil || stopping.contains(id) ? nil : confirming
        case .stopAll?: return servers.isEmpty ? nil : confirming
        case nil: return nil
        }
    }

    func server(_ id: pid_t) -> DevServer? { servers.first { $0.id == id } }

    /// Called on the main thread whenever a scan finishes.
    var onUpdate: (([DevServer]) -> Void)?

    private let scanQueue = DispatchQueue(label: "portly.scan", qos: .utility)
    private let killQueue = DispatchQueue(label: "portly.kill", qos: .userInitiated, attributes: .concurrent)

    func refresh() {
        scanQueue.async {
            let result = Scanner.scan()
            DispatchQueue.main.async { self.apply(result) }
        }
    }

    private func apply(_ result: [DevServer]) {
        servers = result
        stopping.formIntersection(result.map(\.id))
        selection = min(selection, max(result.count - 1, 0))
        // The server on the detail page is gone (stopped here or elsewhere): slide back to the list.
        if case .detail(let id) = page, server(id) == nil {
            withAnimation(Self.slide) { page = .list }
        }
        onUpdate?(result)
    }

    // MARK: - Navigation

    static let slide = Animation.spring(response: 0.32, dampingFraction: 0.88)

    func openDetail(_ server: DevServer, confirmStop: Bool = false) {
        withAnimation(Self.slide) {
            confirming = confirmStop ? .stop(server.id) : nil
            page = .detail(server.id)
        }
    }

    func openDetailForSelected() {
        guard servers.indices.contains(selection) else { return }
        openDetail(servers[selection])
    }

    func back() {
        withAnimation(Self.slide) {
            confirming = nil
            page = .list
        }
    }

    /// Back to the list with nothing pending, e.g. when the panel reopens.
    func reset() {
        page = .list
        confirming = nil
    }

    // MARK: - Stopping (always confirmed)

    func requestStop(_ server: DevServer) {
        withAnimation(.easeOut(duration: 0.18)) { confirming = .stop(server.id) }
    }

    func requestStopAll() {
        guard !servers.isEmpty else { return }
        withAnimation(Self.slide) {
            page = .list
            confirming = .stopAll
        }
    }

    func cancelConfirm() {
        withAnimation(.easeOut(duration: 0.18)) { confirming = nil }
    }

    func confirm() {
        switch activeConfirm {
        case .stop(let id)?: server(id).map(kill)
        case .stopAll?: servers.forEach(kill)
        case nil: return
        }
        withAnimation(.easeOut(duration: 0.18)) { confirming = nil }
    }

    // MARK: - Actions

    private func kill(_ server: DevServer) {
        guard !stopping.contains(server.id) else { return }
        stopping.insert(server.id)
        killQueue.async {
            Scanner.kill(rootPid: server.id)
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func open(_ server: DevServer, port: Int? = nil) {
        guard let port = port ?? server.primaryPort, let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ server: DevServer, port: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port)", forType: .string)
    }

    func reveal(_ server: DevServer) {
        NSWorkspace.shared.open(URL(fileURLWithPath: server.directory, isDirectory: true))
    }

    func openTerminal(_ server: DevServer) {
        guard let app = Apps.terminal else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: server.directory, isDirectory: true)], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func moveSelection(_ delta: Int) {
        guard !servers.isEmpty else { return }
        selection = (selection + delta + servers.count) % servers.count
    }

    private static let loginOptOutKey = "launchAtLoginOptOut"

    /// Launch at login is on by default; re-registering on every start also heals the login item
    /// after a rebuild changes the ad-hoc signature. Turning it off in the ⋯ menu sticks.
    func ensureLaunchAtLogin() {
        guard !UserDefaults.standard.bool(forKey: Self.loginOptOutKey),
              SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Portly: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        let enable = SMAppService.mainApp.status != .enabled
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Portly: launch at login failed: \(error)")
        }
        UserDefaults.standard.set(!enable, forKey: Self.loginOptOutKey)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
