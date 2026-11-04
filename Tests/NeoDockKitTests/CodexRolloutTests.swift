import Foundation
import Testing
@testable import NeoDockKit

@Suite struct CodexRolloutTests {
    func line(_ type: String, _ payload: String, at ts: String = "2026-10-28T19:37:02.039Z") -> String {
        #"{"timestamp":"\#(ts)","type":"\#(type)","payload":\#(payload)}"#
    }

    @Test("letzter Task-Event zählt")
    func lastTask() {
        let tail = CodexRollout.parse(lines: [
            line("event_msg", #"{"type":"task_started"}"#),
            line("event_msg", #"{"type":"token_count"}"#),
            line("event_msg", #"{"type":"task_complete"}"#, at: "2026-10-28T19:40:00.500Z"),
        ])
        #expect(tail.lastTask == .complete)
        #expect(tail.lastTaskAt == Date(timeIntervalSince1970: 1793216400.5))
        #expect(tail.waitingForUser == false)
    }

    @Test("abgeschnittene erste Zeile wird übersprungen")
    func partialLine() {
        let tail = CodexRollout.parse(lines: [
            #"ayload":{"type":"task_complete"}}"#,
            line("event_msg", #"{"type":"task_started"}"#),
        ])
        #expect(tail.lastTask == .started)
    }

    @Test("offene Rückfrage an den Menschen heißt warten")
    func waiting() {
        let open = CodexRollout.parse(lines: [
            line("event_msg", #"{"type":"task_started"}"#),
            line("response_item", #"{"type":"function_call","name":"request_user_input","call_id":"c1"}"#),
        ])
        #expect(open.waitingForUser)
        let answered = CodexRollout.parse(lines: [
            line("event_msg", #"{"type":"task_started"}"#),
            line("response_item", #"{"type":"function_call","name":"request_user_input","call_id":"c1"}"#),
            line("response_item", #"{"type":"function_call_output","call_id":"c1"}"#),
        ])
        #expect(answered.waitingForUser == false)
    }

    @Test("Freigabe-Anfrage ohne Antwort heißt warten")
    func permissions() {
        let tail = CodexRollout.parse(lines: [
            line("event_msg", #"{"type":"task_started"}"#),
            line("response_item", #"{"type":"function_call","name":"request_permissions","call_id":"p1"}"#),
        ])
        #expect(tail.waitingForUser)
        #expect(tail.openCalls.map(\.name) == ["request_permissions"])
    }

    @Test("offene Aufrufe aus früheren Turns zählen nicht")
    func previousTurnCalls() {
        let tail = CodexRollout.parse(lines: [
            line("response_item", #"{"type":"function_call","name":"request_user_input","call_id":"alt"}"#),
            line("event_msg", #"{"type":"task_started"}"#),
        ])
        #expect(tail.openCalls.isEmpty)
        #expect(tail.waitingForUser == false)
    }

    @Test("custom_tool_call wird wie function_call verfolgt")
    func customToolCall() {
        let open = CodexRollout.parse(lines: [
            line("event_msg", #"{"type":"task_started"}"#),
            line("response_item", #"{"type":"custom_tool_call","name":"apply_patch","call_id":"x1"}"#),
        ])
        #expect(open.openCalls.map(\.name) == ["apply_patch"])
        let closed = CodexRollout.parse(lines: [
            line("response_item", #"{"type":"custom_tool_call","name":"apply_patch","call_id":"x1"}"#),
            line("response_item", #"{"type":"custom_tool_call_output","call_id":"x1"}"#),
        ])
        #expect(closed.openCalls.isEmpty)
    }

    @Test("Zustand aus Rollout und Aktivität")
    func state() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = now.addingTimeInterval(-60)
        let old = now.addingTimeInterval(-3600)
        let started = CodexRollout.Tail(lastTask: .started, lastTaskAt: old, waitingForUser: false, openCalls: [])
        #expect(CodexSessionSource.state(tail: started, lastWrite: fresh, now: now).0 == .working)
        // Läuft ein Turn, schreibt aber seit 10 min nichts mehr, wartet er meist auf eine Freigabe.
        let stalled = CodexSessionSource.state(tail: started, lastWrite: old, now: now)
        #expect(stalled.0 == .needsYou)
        #expect(stalled.1 == "still seit über 10 min – Freigabe?")
        let asking = CodexRollout.Tail(lastTask: .started, lastTaskAt: old, waitingForUser: true, openCalls: [])
        #expect(CodexSessionSource.state(tail: asking, lastWrite: fresh, now: now).0 == .needsYou)
        let done = CodexRollout.Tail(lastTask: .complete, lastTaskAt: old, waitingForUser: false, openCalls: [])
        #expect(CodexSessionSource.state(tail: done, lastWrite: fresh, now: now).0 == .ready)
        // Kein Task-Event gefunden: frische Datei heißt arbeitet, nie „bereit“ aus Unwissen.
        let unknown = CodexRollout.Tail(lastTask: nil, lastTaskAt: nil, waitingForUser: false, openCalls: [])
        #expect(CodexSessionSource.state(tail: unknown, lastWrite: fresh, now: now).0 == .working)
    }

    @Test("Task-Event weiter vorn als 64 KB wird durch Rückwärtslesen gefunden")
    func readsBackUntilTaskEvent() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rollout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let filler = String(repeating: line("event_msg", #"{"type":"token_count"}"#) + "\n", count: 4000)
        try (line("event_msg", #"{"type":"task_started"}"#) + "\n" + filler).write(to: url, atomically: true, encoding: .utf8)
        #expect(filler.utf8.count > 65_536)
        #expect(CodexRollout.readTail(url: url)?.lastTask == .started)
    }

    @Test("Originator aus der ersten Rollout-Zeile")
    func originator() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rollout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try (#"{"type":"session_meta","payload":{"id":"t","cwd":"/x","originator":"Codex Desktop","base_instructions":{"text":"lang"}}}"#
             + "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(CodexRollout.originator(url: url) == "Codex Desktop")
        #expect(CodexRollout.originator(url: URL(filePath: "/nonexistent")) == nil)
    }

    @Test("Host-Zuordnung über den Originator", arguments: [
        ("Codex Desktop", CodexHost.desktop), ("codex_work_desktop", .desktop), ("codex_vscode", .vscode),
        ("codex-tui", .cli), ("codex_exec", .exec), ("irgendwas", .unknown),
    ])
    func host(originator: String, expected: CodexHost) {
        #expect(CodexHost(originator: originator, source: "vscode") == expected)
    }

    @Test("nicht lesbare Datei meldet nil statt eines leeren Stands")
    func unreadable() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rollout-\(UUID().uuidString).jsonl")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        #expect(CodexRollout.readTail(url: url) == nil)
    }

    @Test("readTail liest nur das Ende einer großen Datei")
    func readTail() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rollout-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let filler = String(repeating: line("event_msg", #"{"type":"token_count"}"#) + "\n", count: 2000)
        try (line("event_msg", #"{"type":"task_complete"}"#) + "\n" + filler
             + line("event_msg", #"{"type":"task_started"}"#) + "\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(CodexRollout.readTail(url: url, firstChunk: 4096)?.lastTask == .started)
    }
}
