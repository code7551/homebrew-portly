import AppKit

/// The apps behind the action card's buttons, resolved once so their real icons can be shown.
enum Apps {
    static let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "http://localhost")!)
    static let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
    /// Warp if installed, otherwise Terminal.
    static let terminal = ["dev.warp.Warp-Stable", "com.apple.Terminal"].lazy
        .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first

    static func icon(_ app: URL?) -> NSImage {
        guard let app else { return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: app.path)
    }

    static func name(_ app: URL?) -> String {
        app.map { $0.deletingPathExtension().lastPathComponent } ?? "—"
    }
}
