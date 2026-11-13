import AppKit

/// The apps behind the action card's buttons, so their real icons can be shown.
enum Apps {
    private static let web = URL(string: "http://localhost")!
    static var defaultBrowser: URL? { NSWorkspace.shared.urlForApplication(toOpen: web) }
    /// Every installed app that opens web pages, one per bundle id, by name.
    static var browsers: [(id: String, app: URL)] {
        var seen: Set<String> = []
        return NSWorkspace.shared.urlsForApplications(toOpen: web)
            .compactMap { app in Bundle(url: app)?.bundleIdentifier.map { (id: $0, app: app) } }
            .filter { seen.insert($0.id).inserted }
            .sorted { name($0.app).localizedStandardCompare(name($1.app)) == .orderedAscending }
    }
    /// The browser picked in the ⋯ menu; the system default when none is picked or it's been uninstalled.
    static func browser(_ id: String?) -> URL? {
        id.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } ?? defaultBrowser
    }
    static let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
    /// Terminals that open a new window in a folder handed to them like a document. macOS has no default terminal.
    private static let terminalIDs = ["dev.warp.Warp-Stable", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.apple.Terminal"]
    /// The installed ones, by name.
    static var terminals: [(id: String, app: URL)] {
        terminalIDs.compactMap { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id: id, app: $0) } }
            .sorted { name($0.app).localizedStandardCompare(name($1.app)) == .orderedAscending }
    }
    /// The terminal picked in the ⋯ menu; Warp if installed, otherwise Terminal, when none is picked or it's been uninstalled.
    static func terminal(_ id: String?) -> URL? {
        ([id].compactMap { $0 } + ["dev.warp.Warp-Stable", "com.apple.Terminal"]).lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    typealias Editor = (id: String, name: String, app: URL)
    /// Editors that open a folder handed to them like a document, in the order one is chosen when none is picked:
    /// VS Code, VS Code Insiders, Cursor, Windsurf, Zed, Sublime Text.
    private static let editorIDs = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
                                    "com.exafunction.windsurf", "dev.zed.Zed", "com.sublimetext.4"]
    /// Claude Code isn't an app: it opens through its claude-cli:// deep link, in the terminal `claude` last ran in.
    static let claudeCode = "claude-code"
    /// The installed editors by name, then Claude Code once its deep link is registered.
    static var editors: [Editor] {
        editorIDs.compactMap(editor(id:)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            + [editor(id: claudeCode)].compactMap { $0 }
    }
    /// The editor picked in the ⋯ menu; the first installed one when none is picked or it's been uninstalled.
    static func editor(_ id: String?) -> Editor? {
        ([id].compactMap { $0 } + editorIDs + [claudeCode]).lazy.compactMap(editor(id:)).first
    }
    private static func editor(id: String) -> Editor? {
        guard id == claudeCode else {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map {
                (id, name($0).replacingOccurrences(of: "Visual Studio Code", with: "VS Code"), $0)
            }
        }
        // The handler has no icon of its own: borrow the Claude app's when it's installed.
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "claude-cli://open")!) else { return nil }
        return (id, "Claude Code", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") ?? handler)
    }

    static func icon(_ app: URL?) -> NSImage {
        guard let app else { return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: app.path)
    }

    static func name(_ app: URL?) -> String {
        app.map { $0.deletingPathExtension().lastPathComponent } ?? "—"
    }
}
