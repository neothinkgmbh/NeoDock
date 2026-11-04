import AppKit
import NeoDockKit
import os

/// Holt die App einer Sitzung nach vorne, in Terminal.app auch den richtigen Tab. Aktiviert wird
/// über LaunchServices (openApplication), weil eine Hintergrund-App wie NeoDock andere Apps seit
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
        if Bundle(url: url)?.bundleIdentifier == terminalID { selectTerminalTab(of: session) }
    }

    private static let terminalID = "com.apple.Terminal"

    /// Ohne Automation-Freigabe bleibt es beim Aktivieren oben, das Skript schlägt dann nur fehl.
    private static func selectTerminalTab(of session: AgentSession) {
        let pid = session.tool == .claude ? session.pid : ProcessTree.codexCLI(in: session.cwd)
        guard let tty = pid.flatMap(ProcessTable.terminalPath(of:)), let script = TerminalTab.selectScript(tty: tty) else { return }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            if finished.terminationStatus != 0 { log.notice("Terminal-Tab nicht gewählt, Status \(finished.terminationStatus)") }
        }
        do {
            try process.run()
        } catch {
            log.error("osascript nicht startbar: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func hostAppURL(for session: AgentSession) -> URL? {
        switch session.tool {
        case .claude:
            if session.origin?.hasPrefix("claude-desktop") == true {
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: ToolIcons.claudeAppID)
            }
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
