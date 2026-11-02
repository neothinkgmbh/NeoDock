import Foundation

/// Laufende Claude-Code-Sitzungen aus der Registry `~/.claude/sessions/<pid>.json`,
/// die Claude Code selbst pflegt (status: busy | idle | waiting | shell).
public struct ClaudeSessionSource: Sendable {
    public let directory: URL
    let home: String
    let isAlive: @Sendable (Int32) -> Bool
    let startTime: @Sendable (Int32) -> Date?
    /// Toleranz zwischen procStart (Sekundengenau) und der Startzeit des Kernels.
    static let startTolerance: TimeInterval = 2

    public init(directory: URL? = nil, home: String = NSHomeDirectory(),
                isAlive: @escaping @Sendable (Int32) -> Bool = ProcessProbe.isAlive,
                startTime: @escaping @Sendable (Int32) -> Date? = ProcessTable.startTime(of:)) {
        self.home = home
        self.directory = directory ?? URL(filePath: home).appending(path: ".claude/sessions")
        self.isAlive = isAlive
        self.startTime = startTime
    }

    public func sessions() -> [AgentSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { data in Self.session(from: data, home: home).map { ($0, Self.procStart(in: data)) } }
            .filter { session, procStart in isRunning(session.pid, procStart: procStart) }
            .map { withQuestionCheck($0.0) }
    }

    /// `idle` nach einer Rückfrage heißt: wartet auf dich. Das steht nur im Transkript.
    private func withQuestionCheck(_ session: AgentSession) -> AgentSession {
        guard session.state == .ready, session.detail == nil,
              let url = ClaudeTranscript.url(for: session.id, projectsRoot: projectsRoot),
              ClaudeTranscript.endsWithQuestion(url: url) else { return session }
        return AgentSession(tool: session.tool, id: session.id, pid: session.pid, name: session.name,
                            project: session.project, cwd: session.cwd, state: .needsYou, detail: "Frage an dich",
                            since: session.since, origin: session.origin)
    }

    var projectsRoot: URL { URL(filePath: home).appending(path: ".claude/projects") }

    /// Lebt die PID — und ist es noch derselbe Prozess? Registry-Dateien toter Sitzungen bleiben
    /// liegen; wird ihre PID neu vergeben, verrät das die abweichende Startzeit.
    private func isRunning(_ pid: Int32?, procStart: Date?) -> Bool {
        guard let pid, isAlive(pid) else { return false }
        guard let procStart, let actual = startTime(pid) else { return true }
        return abs(actual.timeIntervalSince(procStart)) <= Self.startTolerance
    }

    private struct ProcStartEntry: Decodable { let procStart: String? }

    static func procStart(in data: Data) -> Date? {
        (try? JSONDecoder().decode(ProcStartEntry.self, from: data))?.procStart.flatMap(parseProcStart)
    }

    /// procStart steht als ctime-Text in UTC, z. B. "Mon Nov  2 06:01:12 2026".
    static func parseProcStart(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: text.split(separator: " ").joined(separator: " "))
    }

    private struct Entry: Decodable {
        let pid: Int32?
        let sessionId: String?
        let cwd: String?
        let name: String?
        let status: String?
        let waitingFor: String?
        let statusUpdatedAt: Double?
        let updatedAt: Double?
        let entrypoint: String?
        let parkedJobId: String?
    }

    static func session(from data: Data, home: String) -> AgentSession? {
        guard let e = try? JSONDecoder().decode(Entry.self, from: data),
              let pid = e.pid, let sid = e.sessionId, !sid.isEmpty,
              e.parkedJobId == nil else { return nil }
        let (state, detail) = state(status: e.status, waitingFor: e.waitingFor)
        let cwd = e.cwd ?? ""
        let stamp = e.statusUpdatedAt ?? e.updatedAt
        return AgentSession(
            tool: .claude, id: sid, pid: pid,
            name: (e.name?.isEmpty == false ? e.name : nil) ?? String(sid.prefix(8)),
            project: PathLabel.project(cwd: cwd, home: home), cwd: cwd,
            state: state, detail: detail,
            since: stamp.map { Date(timeIntervalSince1970: $0 / 1000) },
            origin: e.entrypoint)
    }

    static func state(status: String?, waitingFor: String?) -> (SessionState, String?) {
        switch status {
        case "busy": return (.working, nil)
        case "waiting" where waitingFor == "dialog open":
            // z. B. /config offen: wartet nicht auf eine Entscheidung (so zählt es auch der Leitstand).
            return (.ready, "Dialog offen")
        case "waiting":
            let reasons = ["permission prompt": "Freigabe", "input needed": "Eingabe"]
            return (.needsYou, waitingFor.map { reasons[$0] ?? $0 } ?? "Freigabe")
        case "shell": return (.ready, "Hintergrund-Shell")
        default: return (.ready, nil)
        }
    }
}
