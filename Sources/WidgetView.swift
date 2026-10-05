import SwiftUI

/// Two pages that slide like a navigation stack: the server list, and a detail page for one server.
struct WidgetView: View {
    @ObservedObject var store: Store

    var body: some View {
        ZStack(alignment: .top) {
            switch store.page {
            case .list:
                ListPage(store: store)
                    .transition(.move(edge: .leading))
            case .detail(let id):
                if let server = store.server(id) {
                    DetailPage(store: store, server: server)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(width: 380)
        .clipped()
        // Pin to the top while the panel animates to the new page's height.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - List page

private struct ListPage: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.servers.isEmpty {
                empty
            } else if store.servers.count > 6 {
                ScrollView { rows }.frame(height: 6 * 58)
            } else {
                rows
            }
            Divider()
            if store.activeConfirm == .stopAll {
                stopAllBar
            } else {
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: PortlyIcon.image(filled: true, size: 18))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text("Portly")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            StatusPill(text: store.servers.isEmpty ? "All quiet" : "\(store.servers.count) running",
                       color: store.servers.isEmpty ? .secondary : .green)
        }
        .frame(height: 40)
        .padding(.horizontal, 14)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                ServerRow(store: store, server: server, index: index)
            }
        }
        .padding(6)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(nsImage: PortlyIcon.image(filled: false, size: 30))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
                .opacity(0.6)
                .padding(.bottom, 2)
            Text("All ports are quiet")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Start a dev server and it'll show up here")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !store.servers.isEmpty {
                KeyHint(title: "Select", key: "↑↓")
                KeyHint(title: "Open", key: "↩")
            }
            KeyHint(title: "Close", key: "esc")
            Spacer()
            Menu {
                Button("Stop All…", action: store.requestStopAll)
                    .disabled(store.servers.isEmpty)
                Button("Refresh  ⌘R", action: store.refresh)
                Divider()
                Toggle("Launch at Login", isOn: Binding(get: { store.launchAtLogin }, set: { _ in store.toggleLaunchAtLogin() }))
                Text("Show Portly: ⌃⌥B")
                Divider()
                Button("Quit Portly  ⌘Q") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 34)
        .padding(.horizontal, 14)
    }

    private var stopAllBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(store.servers.count == 1 ? "Stop 1 server?" : "Stop all \(store.servers.count) servers?")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button { store.cancelConfirm() } label: { ConfirmLabel(title: "Cancel", key: "esc") }
                .buttonStyle(ConfirmButtonStyle(destructive: false))
                .frame(width: 92)
            Button { store.confirm() } label: { ConfirmLabel(title: "Stop All", key: "↩") }
                .buttonStyle(ConfirmButtonStyle(destructive: true))
                .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .transition(.opacity)
    }
}

private struct ServerRow: View {
    @ObservedObject var store: Store
    let server: DevServer
    let index: Int

    private var selected: Bool { store.selection == index }
    private var stopping: Bool { store.stopping.contains(server.id) }

    var body: some View {
        HStack(spacing: 10) {
            PortBadge(store: store, server: server)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    ScriptChip(server: server)
                    if let pkg = server.distinctPackageName {
                        Text(pkg)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Text(details)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if stopping {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? .secondary : .tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.16) : Color.clear))
        .opacity(stopping ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { if $0 { store.selection = index } }
        .onTapGesture { store.openDetail(server) }
        .contextMenu {
            ForEach(server.ports, id: \.self) { port in
                Button("Open http://localhost:\(port)") { store.open(server, port: port) }
            }
            if let port = server.primaryPort {
                Button("Copy URL") { store.copyURL(server, port: port) }
            }
            Button("Open in Finder") { store.reveal(server) }
            Button("Open in \(Apps.name(Apps.terminal))") { store.openTerminal(server) }
            Divider()
            Button("Stop Server…") { store.openDetail(server, confirmStop: true) }
        }
    }

    private var details: String {
        var parts: [String] = []
        if server.ports.count > 1 { parts.append("+" + server.ports.dropFirst().map { ":\($0)" }.joined(separator: " ")) }
        parts.append(abbreviate(server.directory))
        if server.primaryPort == nil { parts.append("starting…") }
        if let command = server.command { parts.append(command) }
        parts.append(uptime(since: server.startedAt))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Detail page

private struct DetailPage: View {
    @ObservedObject var store: Store
    let server: DevServer

    private var stopping: Bool { store.stopping.contains(server.id) }
    private var confirming: Bool { store.activeConfirm == .stop(server.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                info
                HStack(spacing: 8) {
                    ActionTile(title: server.primaryPort.map { "localhost:\($0)" } ?? "Not listening", key: "↩") {
                        AppIcon(Apps.browser)
                    } action: { store.open(server) }
                        .disabled(server.primaryPort == nil)
                    ActionTile(title: "Finder", key: "F") { AppIcon(Apps.finder) } action: { store.reveal(server) }
                    ActionTile(title: Apps.name(Apps.terminal), key: "T") { AppIcon(Apps.terminal) } action: {
                        store.openTerminal(server)
                    }
                }
                stopSection
            }
            .padding(14)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BackButton { store.back() }
            Text(server.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            ScriptChip(server: server)
            Spacer(minLength: 4)
            StatusPill(text: stopping ? "Stopping…" : "Running", color: stopping ? .orange : .green)
        }
        .frame(height: 40)
        .padding(.leading, 8)
        .padding(.trailing, 14)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 7) {
            if server.ports.isEmpty {
                Text("Not listening on a port yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(server.ports, id: \.self) { port in
                        Button { store.open(server, port: port) } label: {
                            Text(verbatim: ":\(port)")
                                .font(.system(size: port == server.primaryPort ? 15 : 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 9)
                                .frame(height: port == server.primaryPort ? 30 : 24)
                                .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.13)))
                        }
                        .buttonStyle(.plain)
                        .help("Open http://localhost:\(port)")
                    }
                }
            }
            InfoLine(symbol: "folder", text: abbreviate(server.directory))
            if let command = server.command {
                InfoLine(symbol: "chevron.left.forwardslash.chevron.right", text: command, monospaced: true)
            }
            if let pkg = server.distinctPackageName {
                InfoLine(symbol: "shippingbox", text: pkg)
            }
            InfoLine(symbol: "clock", text: "Up \(uptime(since: server.startedAt)) · PID \(server.id)")
        }
    }

    @ViewBuilder private var stopSection: some View {
        if stopping {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Stopping…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        } else if confirming {
            VStack(spacing: 8) {
                Text("Stop \(server.name)? Its whole process tree will be terminated.")
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Button { store.cancelConfirm() } label: { ConfirmLabel(title: "Cancel", key: "esc") }
                        .buttonStyle(ConfirmButtonStyle(destructive: false))
                    Button { store.confirm() } label: { ConfirmLabel(title: "Stop Server", key: "↩") }
                        .buttonStyle(ConfirmButtonStyle(destructive: true))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
            .transition(.opacity)
        } else {
            Button { store.requestStop(server) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("Stop Server")
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(StopButtonStyle())
            .transition(.opacity)
        }
    }
}

// MARK: - Pieces

private struct PortBadge: View {
    @ObservedObject var store: Store
    let server: DevServer

    var body: some View {
        Button { store.open(server) } label: {
            Text(verbatim: server.primaryPort.map { ":\($0)" } ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(server.primaryPort == nil ? Color.secondary : Color.accentColor)
                .frame(width: 58, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill((server.primaryPort == nil ? Color.secondary : Color.accentColor).opacity(0.13)))
        }
        .buttonStyle(.plain)
        .disabled(server.primaryPort == nil)
        .help(server.primaryPort.map { "Open http://localhost:\($0)" } ?? "Not listening yet")
    }
}

private struct ScriptChip: View {
    let server: DevServer

    var body: some View {
        Text(verbatim: "\(server.manager) \(server.script)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15)))
            .fixedSize()
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .fixedSize()
    }
}

private struct InfoLine: View {
    let symbol: String
    let text: String
    var monospaced = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct BackButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Back (esc)")
    }
}

private struct ActionTile<Icon: View>: View {
    let title: String
    let key: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon()
                    .frame(width: 36, height: 36)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(key)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovering ? 0.1 : 0.045)))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AppIcon: View {
    let app: URL?
    init(_ app: URL?) { self.app = app }

    var body: some View {
        Image(nsImage: Apps.icon(app))
            .resizable()
            .interpolation(.high)
    }
}

/// "Open ↩" — an action with its key, dimmed, like the confirm buttons.
private struct KeyHint: View {
    let title: String
    let key: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(key).opacity(0.6)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

private struct ConfirmLabel: View {
    let title: String
    let key: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(key).font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

private struct ConfirmButtonStyle: ButtonStyle {
    let destructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(destructive ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7).fill(
                destructive ? Color.red.opacity(configuration.isPressed ? 0.75 : 1)
                            : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)
            ))
            .contentShape(Rectangle())
    }
}

/// Red-tinted full-width button; a hover state needs a view, hence the inner body.
private struct StopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.red)
                .background(RoundedRectangle(cornerRadius: 8).fill(
                    Color.red.opacity(configuration.isPressed ? 0.22 : hovering ? 0.16 : 0.1)
                ))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

private func abbreviate(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

private func uptime(since date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    switch s {
    case ..<60: return "\(s)s"
    case ..<3600: return "\(s / 60)m"
    case ..<86400: return "\(s / 3600)h \(s % 3600 / 60)m"
    default: return "\(s / 86400)d \(s % 86400 / 3600)h"
    }
}
