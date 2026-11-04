import Foundation
import Testing
@testable import NeoDockKit

@Suite struct ClaudeTranscriptTests {
    func assistant(_ parts: String) -> String { #"{"type":"assistant","message":{"role":"assistant","content":[\#(parts)]}}"# }
    let toolUse = #"{"type":"tool_use","name":"Bash"}"#
    func text(_ t: String) -> String { #"{"type":"text","text":"\#(t)"}"# }
    let toolResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result"}]}}"#
    let human = #"{"type":"user","message":{"role":"user","content":"ja, mach"}}"#

    @Test("ein Lesefehler bleibt nicht hängen: Eine wartende Sitzung schreibt nichts mehr, die Datei ändert sich also nicht")
    func readFailureIsNotRemembered() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "transcript-\(UUID().uuidString).jsonl")
        try Data(assistant(text("Soll ich deployen?")).utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        #expect(!ClaudeTranscript.endsWithQuestion(url: url))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(ClaudeTranscript.endsWithQuestion(url: url))
    }

    @Test("Frage am Zugende wartet auf den Menschen — auch mit Markdown dahinter")
    func question() {
        #expect(ClaudeTranscript.endsWithQuestion(lines: [assistant(toolUse), toolResult, assistant(text("Soll ich deployen?"))]))
        #expect(ClaudeTranscript.endsWithQuestion(lines: [assistant(text("Passt das so? **"))]))
    }

    @Test("keine Frage, danach Werkzeug, oder schon beantwortet: kein Warten")
    func noQuestion() {
        #expect(!ClaudeTranscript.endsWithQuestion(lines: [assistant(text("Fertig."))]))
        #expect(!ClaudeTranscript.endsWithQuestion(lines: [assistant(text("Soll ich?")), assistant(toolUse)]))
        #expect(!ClaudeTranscript.endsWithQuestion(lines: [assistant(text("Soll ich?")), human]))
        #expect(!ClaudeTranscript.endsWithQuestion(lines: [String]()))
    }

    @Test("Denkblöcke ohne Text ändern nichts am letzten Text")
    func thinking() {
        let thinking = assistant(#"{"type":"thinking","thinking":"hm"}"#)
        #expect(ClaudeTranscript.endsWithQuestion(lines: [assistant(text("Welche Variante?")), thinking]))
    }
}
