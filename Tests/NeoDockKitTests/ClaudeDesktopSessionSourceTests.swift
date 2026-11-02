import Foundation
import Testing
@testable import NeoDockKit

@Suite struct ClaudeDesktopSessionSourceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func write(_ json: String, to dir: URL, name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appending(path: name))
    }

    func session(id: String, cli: String, title: String, minutesAgo: Double, archived: Bool = false) -> String {
        let ms = Int64((now.timeIntervalSince1970 - minutesAgo * 60) * 1000)
        return #"{"sessionId":"\#(id)","cliSessionId":"\#(cli)","cwd":"/Users/t/Projekte/Demo","title":"\#(title)","lastActivityAt":\#(ms),"isArchived":\#(archived)}"#
    }

    @Test("liest Code- und Agenten-Sitzungen der Desktop-App: aktuell, nicht archiviert, ohne Doppel")
    func reads() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "claude-desktop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let code = root.appending(path: "claude-code-sessions/acc/org")
        let cowork = root.appending(path: "local-agent-mode-sessions/acc/org")
        try write(session(id: "local_a", cli: "cli-a", title: "Polestar Kilometer", minutesAgo: 5), to: code, name: "local_a.json")
        try write(session(id: "local_b", cli: "cli-b", title: "Alt", minutesAgo: 600), to: code, name: "local_b.json")
        try write(session(id: "local_c", cli: "cli-c", title: "Archiv", minutesAgo: 5, archived: true), to: code, name: "local_c.json")
        try write(session(id: "local_d", cli: "cli-d", title: "Schon in Claude Code", minutesAgo: 1), to: code, name: "local_d.json")
        try write(session(id: "local_e", cli: "cli-e", title: "Recherche", minutesAgo: 1), to: cowork, name: "local_e.json")
        try write("{}", to: code, name: "scheduled-tasks.json")

        let source = ClaudeDesktopSessionSource(appSupport: root, home: "/Users/t")
        let sessions = source.sessions(now: now, isAppRunning: true, knownCliIDs: ["cli-d"])
        #expect(Set(sessions.map(\.name)) == ["Polestar Kilometer", "Recherche"])
        let recherche = try #require(sessions.first { $0.name == "Recherche" })
        #expect(recherche.tool == .claude)
        #expect(recherche.state == .working)          // Agentenmodus: frische Aktivität = arbeitet
        #expect(recherche.origin == ClaudeDesktopSessionSource.coworkOrigin)
        #expect(recherche.project == "Demo")
        let polestar = try #require(sessions.first { $0.name == "Polestar Kilometer" })
        #expect(polestar.state == .ready)             // vor 5 min, kein Transkript gefunden
        #expect(polestar.origin == ClaudeDesktopSessionSource.codeOrigin)
    }

    @Test("ohne laufende Claude-App gibt es keine Desktop-Sitzungen")
    func appNotRunning() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "claude-desktop-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try write(session(id: "local_a", cli: "cli-a", title: "A", minutesAgo: 1),
                  to: root.appending(path: "claude-code-sessions/acc/org"), name: "local_a.json")
        #expect(ClaudeDesktopSessionSource(appSupport: root, home: "/Users/t")
            .sessions(now: now, isAppRunning: false, knownCliIDs: []).isEmpty)
    }
}
