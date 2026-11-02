import Foundation

public enum AgentTool: String, Sendable, CaseIterable {
    case claude, codex

    public var label: String { self == .claude ? "Claude Code" : "Codex" }
}

/// Reihenfolge = Dringlichkeit: was den Menschen braucht, steht vorn.
public enum SessionState: Int, Sendable, Comparable, CaseIterable {
    case needsYou = 0, working = 1, ready = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .needsYou: "braucht dich"
        case .working: "arbeitet"
        case .ready: "bereit"
        }
    }
}

public struct AgentSession: Sendable, Identifiable, Equatable {
    public let tool: AgentTool
    public let id: String
    public let pid: Int32?
    public let name: String
    public let project: String
    public let cwd: String
    public let state: SessionState
    public let detail: String?
    public let since: Date?
    /// Claude: entrypoint (cli, sdk …). Codex: source (cli, vscode, exec …).
    public let origin: String?

    public init(tool: AgentTool, id: String, pid: Int32?, name: String, project: String, cwd: String,
                state: SessionState, detail: String?, since: Date?, origin: String?) {
        self.tool = tool
        self.id = id
        self.pid = pid
        self.name = name
        self.project = project
        self.cwd = cwd
        self.state = state
        self.detail = detail
        self.since = since
        self.origin = origin
    }
}

public extension [AgentSession] {
    /// Dringendes zuerst, innerhalb eines Zustands das zuletzt Geänderte.
    func sortedByUrgency() -> [AgentSession] {
        sorted {
            if $0.state != $1.state { return $0.state < $1.state }
            return ($0.since ?? .distantPast) > ($1.since ?? .distantPast)
        }
    }
}

enum PathLabel {
    static func project(cwd: String, home: String) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        if trimmed.isEmpty || trimmed == home { return "~" }
        return URL(filePath: trimmed).lastPathComponent
    }
}

public enum ProcessProbe {
    /// kill(pid, 0): 0 = lebt; EPERM = lebt, gehört nur jemand anderem.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
