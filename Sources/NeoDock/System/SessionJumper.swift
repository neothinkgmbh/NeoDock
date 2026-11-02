import AppKit
import NeoDockKit
import os

/// Holt die App einer Sitzung nach vorne (die App, nicht den einzelnen Tab). Aktiviert wird über
/// LaunchServices (openApplication), weil eine Hintergrund-App wie NeoDock andere Apps seit
/// macOS 14 nicht mehr direkt aktivieren darf.
enum SessionJumper {
    nonisolated private static let log = Logger(subsystem: "ai.neothink.neodock", category: "jump")

    static func jump(to session: AgentSession) {
        guard let url = hostAppURL(for: session) else {
            log.notice("Keine App für \(session.name, privacy: .public) gefunden")
            NSSound.beep()
            return
        }
        log.info("Sitzung \(session.name, privacy: .public) → \(url.lastPathComponent, privacy: .public)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log.error("Aktivieren fehlgeschlagen: \(error.localizedDescription, privacy: .public)") }
        }
    }

    static func hostAppURL(for session: AgentSession) -> URL? {
        switch session.tool {
        case .claude:
            return session.pid.flatMap(ProcessTree.owningApp(of:))?.bundleURL
        case .codex:
            switch CodexHost(rawValue: session.origin ?? "") {
            case .desktop?: return CodexHosts.url(.desktop)
            case .vscode?: return CodexHosts.url(.vscode)
            default: return ProcessTree.codexCLI(in: session.cwd).flatMap(ProcessTree.owningApp(of:))?.bundleURL
            }
        }
    }
}

/// Die Apps, in denen Codex-Threads ohne eigenen Terminal-Prozess laufen.
enum CodexHosts {
    static let bundleIDs: [CodexHost: String] = [.desktop: "com.openai.codex", .vscode: "com.microsoft.VSCode"]

    static func url(_ host: CodexHost) -> URL? {
        bundleIDs[host].flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    static func isRunning(_ host: CodexHost) -> Bool {
        guard let id = bundleIDs[host] else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
}
