import Foundation

/// Sitzungen der Claude-Desktop-App: Code-Bereich (`claude-code-sessions`) und Agentenmodus
/// (`local-agent-mode-sessions`). Je Sitzung liegt dort `local_<id>.json` mit Titel, Ordner und
/// letzter Aktivität — nur gelesen. Code-Sitzungen schreiben ihr Transkript wie Claude Code nach
/// `~/.claude/projects`; der Agentenmodus läuft in einer VM, dort zählt die letzte Aktivität.
/// Normale Chats liegen nicht lokal und sind nicht erfassbar.
public struct ClaudeDesktopSessionSource: Sendable {
    public static let codeOrigin = "claude-desktop-code"
    public static let coworkOrigin = "claude-desktop-cowork"
    static let folders = [("claude-code-sessions", codeOrigin), ("local-agent-mode-sessions", coworkOrigin)]

    let appSupport: URL
    let home: String
    public var visibleWindow: TimeInterval = 3 * 3600
    /// Transkript bzw. letzte Aktivität so frisch: die Sitzung arbeitet.
    public static let activeWindow: TimeInterval = 120

    public init(appSupport: URL? = nil, home: String = NSHomeDirectory()) {
        self.home = home
        self.appSupport = appSupport ?? URL(filePath: home).appending(path: "Library/Application Support/Claude")
    }

    private struct Entry: Decodable {
        let sessionId: String?
        let cliSessionId: String?
        let cwd: String?
        let title: String?
        let lastActivityAt: Double?
        let isArchived: Bool?
    }

    /// `knownCliIDs`: Sitzungen, die schon über die Claude-Code-Registry erscheinen (kein Doppel).
    public func sessions(now: Date = Date(), isAppRunning: Bool, knownCliIDs: Set<String>) -> [AgentSession] {
        guard isAppRunning else { return [] }
        let decoder = JSONDecoder()
        let projects = URL(filePath: home).appending(path: ".claude/projects")
        return Self.folders.flatMap { folder, origin in
            sessionFiles(in: appSupport.appending(path: folder)).compactMap { url -> AgentSession? in
                guard let data = try? Data(contentsOf: url), let e = try? decoder.decode(Entry.self, from: data),
                      let id = e.sessionId, e.isArchived != true, let last = e.lastActivityAt else { return nil }
                let lastActivity = Date(timeIntervalSince1970: last / 1000)
                guard now.timeIntervalSince(lastActivity) <= visibleWindow else { return nil }
                if let cli = e.cliSessionId, knownCliIDs.contains(cli) { return nil }
                let transcript = origin == Self.codeOrigin ? e.cliSessionId.flatMap { ClaudeTranscript.url(for: $0, projectsRoot: projects) } : nil
                let (state, detail, since) = Self.state(transcript: transcript, lastActivity: lastActivity, now: now)
                let cwd = e.cwd ?? ""
                return AgentSession(tool: .claude, id: id, pid: nil,
                                    name: (e.title?.isEmpty == false ? e.title : nil) ?? PathLabel.project(cwd: cwd, home: home),
                                    project: PathLabel.project(cwd: cwd, home: home), cwd: cwd,
                                    state: state, detail: detail, since: since, origin: origin)
            }
        }
    }

    static func state(transcript: URL?, lastActivity: Date, now: Date) -> (SessionState, String?, Date) {
        if let transcript {
            let written = (try? transcript.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? lastActivity
            if now.timeIntervalSince(written) <= activeWindow { return (.working, nil, written) }
            if ClaudeTranscript.endsWithQuestion(url: transcript) { return (.needsYou, "Frage an dich", written) }
            return (.ready, nil, written)
        }
        return now.timeIntervalSince(lastActivity) <= activeWindow ? (.working, nil, lastActivity) : (.ready, nil, lastActivity)
    }

    /// `<ordner>/<konto>/<org>/local_*.json` — bewusst nicht rekursiv (im Agentenmodus liegen
    /// darunter Zehntausende Arbeitsdateien).
    private func sessionFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        func dirs(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        return dirs(root).flatMap(dirs).flatMap { org in
            ((try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
        }
    }
}
