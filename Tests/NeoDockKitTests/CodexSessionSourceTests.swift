import Foundation
import SQLite3
import Testing
@testable import NeoDockKit

@Suite struct CodexSessionSourceTests {
    @Test("liest sichtbare Threads, ohne Archiv, Subagenten und Altes")
    func threads() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "codex-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rollout = dir.appending(path: "r1.jsonl")
        try #"{"timestamp":"2026-10-28T19:37:02.039Z","type":"event_msg","payload":{"type":"task_complete"}}"#
            .write(to: rollout, atomically: true, encoding: .utf8)

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let db = dir.appending(path: "state.sqlite").path
        var handle: OpaquePointer?
        #expect(sqlite3_open(db, &handle) == SQLITE_OK)
        let rows = [
            ("a", rollout.path, "/Users/t/Development/Breathermans", "Baue die PWA\nmit Audio", "cli", 0, nowMs - 60_000, ""),
            ("b", rollout.path, "/x", "archiviert", "cli", 1, nowMs, ""),
            ("c", rollout.path, "/x", "", #"{"subagent":{}}"#, 0, nowMs, ""),
            ("d", rollout.path, "/x", "alt", "vscode", 0, nowMs - 5 * 3_600_000, ""),
            ("e", rollout.path, "/Users/t/Docs", "lang", "vscode", 0, nowMs - 1000, "Mein Thread"),
        ]
        var sql = """
        CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, cwd TEXT NOT NULL,
          title TEXT NOT NULL, source TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0, updated_at_ms INTEGER, name TEXT, git_branch TEXT, originator TEXT);
        """
        for r in rows {
            let title = r.3.replacingOccurrences(of: "'", with: "''")
            let name = r.7.isEmpty ? "NULL" : "'\(r.7)'"
            sql += "INSERT INTO threads (id, rollout_path, cwd, title, source, archived, updated_at_ms, name) VALUES ('\(r.0)', '\(r.1)', '\(r.2)', '\(title)', '\(r.4.replacingOccurrences(of: "'", with: "''"))', \(r.5), \(r.6), \(name));"
        }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)

        let sessions = CodexSessionSource(databasePath: db, home: "/Users/t").sessions(now: now)
        #expect(Set(sessions.map(\.id)) == ["a", "e"])
        let a = try #require(sessions.first { $0.id == "a" })
        #expect(a.tool == .codex)
        #expect(a.name == "Baue die PWA")
        #expect(a.project == "Breathermans")
        #expect(a.state == .ready)
        #expect(a.origin == CodexHost.cli.rawValue)
        #expect(sessions.first { $0.id == "e" }?.name == "Mein Thread")
    }

    @Test("fehlende Datenbank liefert leere Liste")
    func missing() {
        #expect(CodexSessionSource(databasePath: "/nonexistent/state.sqlite", home: "/").sessions().isEmpty)
    }
}
