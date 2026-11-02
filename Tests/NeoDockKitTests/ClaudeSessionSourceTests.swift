import Foundation
import Testing
@testable import NeoDockKit

@Suite struct ClaudeSessionSourceTests {
    let home = "/Users/tester"

    func entry(_ status: String, pid: Int = 4182, extra: String = "") -> Data {
        Data("""
        {"pid":\(pid),"sessionId":"81fccb4c-aba9","cwd":"/Users/tester/Development/thrive",
         "name":"thrive-a1","status":"\(status)","statusUpdatedAt":1793606444028,
         "entrypoint":"cli"\(extra)}
        """.utf8)
    }

    @Test("busy heißt arbeitet")
    func busy() throws {
        let s = try #require(ClaudeSessionSource.session(from: entry("busy"), home: home))
        #expect(s.state == .working)
        #expect(s.tool == .claude)
        #expect(s.pid == 4182)
        #expect(s.project == "thrive")
        #expect(s.name == "thrive-a1")
        #expect(s.since == Date(timeIntervalSince1970: 1793606444.028))
    }

    @Test("waiting heißt braucht dich, mit Grund", arguments: [
        ("permission prompt", "Freigabe"), ("input needed", "Eingabe"),
    ])
    func waiting(reason: String, detail: String) throws {
        let data = entry("waiting", extra: #","waitingFor":"\#(reason)""#)
        let s = try #require(ClaudeSessionSource.session(from: data, home: home))
        #expect(s.state == .needsYou)
        #expect(s.detail == detail)
    }

    @Test("ein offener Dialog (z. B. /config) ist kein Alarm")
    func dialogOpen() throws {
        let data = entry("waiting", extra: #","waitingFor":"dialog open""#)
        let s = try #require(ClaudeSessionSource.session(from: data, home: home))
        #expect(s.state == .ready)
        #expect(s.detail == "Dialog offen")
    }

    @Test("procStart wird als UTC gelesen")
    func procStart() {
        #expect(ClaudeSessionSource.parseProcStart("Mon Nov  2 06:01:12 2026")
                == Date(timeIntervalSince1970: 1_793_599_272))
        #expect(ClaudeSessionSource.parseProcStart("Unsinn") == nil)
    }

    @Test("wiederverwendete PID: andere Startzeit heißt tote Sitzung")
    func reusedPID() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try entry("busy", pid: 100, extra: #","procStart":"Mon Nov  2 06:01:12 2026""#)
            .write(to: dir.appending(path: "100.json"))
        let real = Date(timeIntervalSince1970: 1_793_599_272)
        let same = ClaudeSessionSource(directory: dir, home: home, isAlive: { _ in true }, startTime: { _ in real })
        #expect(same.sessions().count == 1)
        let other = ClaudeSessionSource(directory: dir, home: home, isAlive: { _ in true },
                                        startTime: { _ in real.addingTimeInterval(3600) })
        #expect(other.sessions().isEmpty)
    }

    @Test("idle und shell heißen bereit")
    func ready() throws {
        #expect(ClaudeSessionSource.session(from: entry("idle"), home: home)?.state == .ready)
        let shell = try #require(ClaudeSessionSource.session(from: entry("shell"), home: home))
        #expect(shell.state == .ready)
        #expect(shell.detail == "Hintergrund-Shell")
    }

    @Test("geparkte und unvollständige Einträge fallen weg")
    func skipped() {
        #expect(ClaudeSessionSource.session(from: entry("busy", extra: #","parkedJobId":"j1""#), home: home) == nil)
        #expect(ClaudeSessionSource.session(from: Data(#"{"pid":1}"#.utf8), home: home) == nil)
        #expect(ClaudeSessionSource.session(from: Data("kaputt".utf8), home: home) == nil)
    }

    @Test("Home-Verzeichnis heißt ~")
    func homeProject() throws {
        let data = Data(#"{"pid":7,"sessionId":"abc","cwd":"/Users/tester","status":"idle"}"#.utf8)
        let s = try #require(ClaudeSessionSource.session(from: data, home: home))
        #expect(s.project == "~")
        #expect(s.name == "abc")
    }

    @Test("tote Prozesse werden nicht gelistet, Schlüsseldateien ignoriert")
    func directory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try entry("busy", pid: 100).write(to: dir.appending(path: "100.json"))
        try entry("idle", pid: 200).write(to: dir.appending(path: "200.json"))
        try Data("x".utf8).write(to: dir.appending(path: "100.abc.key"))
        let source = ClaudeSessionSource(directory: dir, home: home, isAlive: { $0 == 100 }, startTime: { _ in nil })
        let sessions = source.sessions()
        #expect(sessions.map(\.pid) == [100])
    }
}
