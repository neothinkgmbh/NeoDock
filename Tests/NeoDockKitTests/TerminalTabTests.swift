import Testing
@testable import NeoDockKit

@Suite struct TerminalTabTests {
    @Test func skriptEnthaeltDasTerminal() throws {
        let script = try #require(TerminalTab.selectScript(tty: "/dev/ttys012"))
        #expect(script.contains(#"if tty of t is "/dev/ttys012" then"#))
    }

    @Test("alles andere als ein tty-Pfad kommt nicht ins Skript", arguments: [
        "", "ttys000", "/dev/console", #"/dev/ttys0" then beep"#, "/dev/ttys0\n", "/dev/ttys",
    ])
    func fremderTextWirdAbgelehnt(tty: String) {
        #expect(TerminalTab.selectScript(tty: tty) == nil)
    }
}
