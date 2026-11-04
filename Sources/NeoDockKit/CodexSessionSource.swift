import Foundation
import SQLite3

/// Codex-Threads der letzten Stunden aus `~/.codex/state_5.sqlite` (nur lesend),
/// Zustand aus dem Schwanz der jeweiligen Rollout-Datei.
public struct CodexSessionSource: Sendable {
    public let databasePath: String
    let home: String
    /// Threads, die länger nicht geschrieben wurden, sind keine laufenden Sitzungen mehr.
    public var visibleWindow: TimeInterval = 3 * 3600
    /// Ein gestarteter Task ohne Schreibzugriff in diesem Fenster gilt als still.
    public static let activeWindow: TimeInterval = 10 * 60
    static let nameLimit = 60

    public init(databasePath: String? = nil, home: String = NSHomeDirectory()) {
        self.home = home
        self.databasePath = databasePath ?? URL(filePath: home).appending(path: ".codex/state_5.sqlite").path
    }

    struct Row {
        let id, rolloutPath, cwd, title, source: String
        let name, originator: String?
        let updatedMs: Int64
    }

    private static let tails = FileMemo<CodexRollout.Tail>()

    public func sessions(now: Date = Date()) -> [AgentSession] {
        let since = Int64((now.timeIntervalSince1970 - visibleWindow) * 1000)
        return rows(updatedSinceMs: since).map { row in
            let url = URL(filePath: row.rolloutPath)
            let tail = Self.tails.value(for: url) { CodexRollout.readTail(url: url) } ?? .empty
            let lastWrite = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? Date(timeIntervalSince1970: Double(row.updatedMs) / 1000)
            let (state, detail) = Self.state(tail: tail, lastWrite: lastWrite, now: now)
            let originator = row.originator.flatMap { $0.isEmpty ? nil : $0 } ?? CodexRollout.originator(url: url)
            return AgentSession(
                tool: .codex, id: row.id, pid: nil, name: displayName(row),
                project: PathLabel.project(cwd: row.cwd, home: home), cwd: row.cwd,
                state: state, detail: detail, since: tail.lastTaskAt ?? lastWrite,
                origin: CodexHost(originator: originator, source: row.source).rawValue)
        }
    }

    static func state(tail: CodexRollout.Tail, lastWrite: Date, now: Date) -> (SessionState, String?) {
        if tail.waitingForUser {
            let permission = tail.openCalls.contains { $0.name.hasPrefix("request_permissions") }
            return (.needsYou, permission ? "Freigabe" : "Rückfrage")
        }
        let isFresh = now.timeIntervalSince(lastWrite) <= activeWindow
        switch tail.lastTask {
        case .started?:
            // Freigaben schreibt Codex nicht ins Rollout: ein laufender Turn, der seit Minuten
            // nichts schreibt, wartet meist auf den Menschen.
            return isFresh ? (.working, nil) : (.needsYou, "still seit über 10 min – Freigabe?")
        case nil:
            // Kein Task-Event innerhalb der Leseobergrenze: Unwissen ist nicht „bereit“.
            return isFresh ? (.working, nil) : (.ready, nil)
        case .complete?, .aborted?:
            return (.ready, nil)
        }
    }

    private func displayName(_ row: Row) -> String {
        if let name = row.name, !name.isEmpty { return name }
        let firstLine = row.title.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return PathLabel.project(cwd: row.cwd, home: home) }
        return firstLine.count > Self.nameLimit ? String(firstLine.prefix(Self.nameLimit)) + "…" : firstLine
    }

    private func rows(updatedSinceMs: Int64) -> [Row] {
        guard FileManager.default.fileExists(atPath: databasePath) else { return [] }
        var db: OpaquePointer?
        // Nur lesend: an den Daten ändert NeoDock nichts. Im WAL-Modus trägt aber jeder Leser
        // (auch Codex selbst) Lesemarken in state_5.sqlite-shm ein — das ist SQLites Sperrprotokoll.
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        let sql = """
        SELECT id, rollout_path, cwd, title, source, name, originator, COALESCE(updated_at_ms, updated_at * 1000)
        FROM threads
        WHERE archived = 0 AND source NOT LIKE '{%' AND COALESCE(updated_at_ms, updated_at * 1000) >= ?1
        ORDER BY 8 DESC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, updatedSinceMs)
        var result: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
            result.append(Row(id: text(0) ?? "", rolloutPath: text(1) ?? "", cwd: text(2) ?? "",
                              title: text(3) ?? "", source: text(4) ?? "", name: text(5), originator: text(6),
                              updatedMs: sqlite3_column_int64(stmt, 7)))
        }
        return result
    }
}
