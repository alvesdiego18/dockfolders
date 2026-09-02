// Abertura de pastas e resolução de apps.

import AppKit

enum Opening {

    /// URL efetivamente aberta: o alvo específico do abridor, ou a própria pasta.
    static func targetURL(_ item: FolderItem, _ opener: Opener) -> URL {
        if let t = opener.targetPath, !t.isEmpty { return URL(fileURLWithPath: t) }
        return URL(fileURLWithPath: item.path)
    }

    static func open(_ item: FolderItem, with opener: Opener) {
        let url = targetURL(item, opener)
        guard let bundleID = opener.bundleID else {
            NSWorkspace.shared.open(url)          // Finder
            return
        }
        guard let appURL = appURL(for: bundleID) else {
            NSWorkspace.shared.open(url)          // app sumiu: cai no Finder
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func icon(for opener: Opener) -> NSImage? {
        let id = opener.bundleID ?? "com.apple.finder"
        guard let u = appURL(for: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: u.path)
    }

    static func appName(for opener: Opener) -> String {
        guard let id = opener.bundleID else { return "Finder" }
        guard let u = appURL(for: id) else { return id }
        return FileManager.default.displayName(atPath: u.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    /// Texto do tooltip: só o app, ou "app — arquivo" quando há alvo específico (Q35).
    static func tooltip(for opener: Opener) -> String {
        let name = appName(for: opener)
        guard let t = opener.targetPath, !t.isEmpty else { return name }
        return "\(name) — \((t as NSString).lastPathComponent)"
    }
}
