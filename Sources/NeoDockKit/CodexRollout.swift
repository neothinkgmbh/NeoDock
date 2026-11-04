import Foundation

/// Wo ein Codex-Thread läuft — aus dem `originator` der Sitzung, nicht aus `source`:
/// `source = vscode` meint auf diesem Rechner fast immer die Codex-Desktop-App.
public enum CodexHost: String, Sendable {
    case desktop, vscode, cli, exec, unknown

    public init(originator: String?, source: String) {
        switch originator?.lowercased() {
        case let o? where o.contains("desktop"): self = .desktop
        case let o? where o.contains("vscode"): self = .vscode
        case let o? where o.contains("tui"): self = .cli
        case let o? where o.contains("exec"): self = .exec
        case nil, ""?:
            self = source == "cli" ? .cli : source == "exec" ? .exec : .unknown
        default: self = .unknown
        }
    }
}

/// Liest das Ende einer Codex-Rollout-Datei (JSONL) und leitet daraus ab, ob gerade ein
/// Task läuft, welche Werkzeugaufrufe offen sind und ob Codex auf den Menschen wartet.
/// Codex schreibt Freigabe-Wartezustände NICHT als eigenes Ereignis — sichtbar sind sie nur
/// als Werkzeugaufruf ohne Ausgabe.
public enum CodexRollout {
    public enum TaskEvent: Sendable, Equatable { case started, complete, aborted }

    public struct OpenCall: Sendable, Equatable {
        public let name: String
        public let at: Date?
    }

    public struct Tail: Sendable, Equatable {
        public var lastTask: TaskEvent?
        public var lastTaskAt: Date?
        public var waitingForUser: Bool
        public var openCalls: [OpenCall]

        public static let empty = Tail(lastTask: nil, lastTaskAt: nil, waitingForUser: false, openCalls: [])
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            let type: String?
            let name: String?
            let call_id: String?
        }
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    /// Werkzeuge, mit denen Codex den Menschen fragt.
    static let userFacingTools = ["request_user_input", "request_permissions"]
    static let callTypes: Set<String> = ["function_call", "custom_tool_call"]
    static let outputTypes: Set<String> = ["function_call_output", "custom_tool_call_output"]

    /// Jedes auswertbare Ereignis enthält eines dieser Stücke. Die meisten Bytes eines Rollouts
    /// sind Nachrichten und Werkzeugausgaben; solche Zeilen werden gar nicht erst als JSON zerlegt.
    private static let eventMarkers = ["task_", "turn_aborted", "_call"].map { Data($0.utf8) }

    public static func parse<S: Sequence>(lines: S) -> Tail where S.Element: StringProtocol {
        parse(rawLines: lines.lazy.map { Data($0.utf8) })
    }

    static func parse<S: Sequence>(rawLines: S) -> Tail where S.Element == Data {
        let decoder = JSONDecoder()
        var tail = Tail.empty
        var open: [(id: String, call: OpenCall)] = []
        for raw in rawLines {
            guard eventMarkers.contains(where: { raw.range(of: $0) != nil }),
                  let line = try? decoder.decode(Line.self, from: raw),
                  let payload = line.payload, let kind = payload.type else { continue }
            switch line.type {
            case "event_msg":
                switch kind {
                case "task_started":
                    tail.mark(.started, at: line.timestamp)
                    open.removeAll()  // nur der laufende Turn zählt
                case "task_complete": tail.mark(.complete, at: line.timestamp)
                case "turn_aborted": tail.mark(.aborted, at: line.timestamp)
                default: break
                }
            case "response_item":
                if callTypes.contains(kind), let id = payload.call_id {
                    open.append((id, OpenCall(name: payload.name ?? "?", at: date(line.timestamp))))
                } else if outputTypes.contains(kind), let id = payload.call_id {
                    open.removeAll { $0.id == id }
                }
            default: break
            }
        }
        // Nach einem Turn-Ende ist nichts mehr offen, was auf den Menschen wartet.
        tail.openCalls = tail.lastTask == .started || tail.lastTask == nil ? open.map(\.call) : []
        tail.waitingForUser = tail.openCalls.contains { call in userFacingTools.contains { call.name.hasPrefix($0) } }
        return tail
    }

    /// Liest von hinten in wachsenden Blöcken, bis ein Task-Event dabei ist oder die Obergrenze
    /// erreicht ist: lange Turns schreiben nach task_started oft Megabytes.
    public static func readTail(url: URL, firstChunk: Int = 65_536, limit: Int = 16 << 20) -> Tail {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        let size = Int((try? handle.seekToEnd()) ?? 0)
        var chunk = min(firstChunk, size)
        while true {
            try? handle.seek(toOffset: UInt64(size - chunk))
            let data = (try? handle.read(upToCount: chunk)) ?? Data()
            let tail = parse(rawLines: data.split(separator: UInt8(ascii: "\n")))
            if tail.lastTask != nil || chunk >= size || chunk >= limit { return tail }
            chunk = min(chunk * 4, size, limit)
        }
    }

    static let headBytes = 262_144

    /// `originator` steht in der ersten Zeile (session_meta) vor den langen Basisanweisungen.
    public static func originator(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: headBytes)) ?? Data(), as: UTF8.self)
        return head.firstMatch(of: /"originator":"([^"]*)"/).map { String($0.1) }
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
    }
}

private extension CodexRollout.Tail {
    mutating func mark(_ event: CodexRollout.TaskEvent, at timestamp: String?) {
        lastTask = event
        lastTaskAt = CodexRollout.date(timestamp) ?? lastTaskAt
    }
}
