import Foundation
import Testing
@testable import NeoDockKit

@Suite(.serialized) struct SystemDockGuardTests {
    let domain = "ai.neothink.neodock.guardtest"

    func defaults(_ args: String...) -> String {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/defaults")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("Wächter stellt nach Ende der Pipe die Originale wieder her — auch einen fehlenden Schlüssel")
    func watchdogRestores() throws {
        _ = defaults("delete", domain)
        _ = defaults("write", domain, "autohide", "-bool", "false")
        // autohide-delay fehlt ursprünglich
        let originals = SystemDockGuard.readOriginals(domain: domain)
        #expect(originals["autohide"] == .bool(false))
        #expect(originals["autohide-delay"] == .absent)

        let watchdog = Process()
        watchdog.executableURL = URL(filePath: "/bin/sh")
        watchdog.arguments = ["-c", SystemDockGuard.watchdogScript(domain: domain, originals: originals, restart: "true")]
        let pipe = Pipe()
        watchdog.standardInput = pipe
        try watchdog.run()

        for command in SystemDockGuard.hideCommands(domain: domain) {
            let p = Process()
            p.executableURL = URL(filePath: "/bin/sh")
            p.arguments = ["-c", command]
            try p.run()
            p.waitUntilExit()
        }
        #expect(defaults("read", domain, "autohide") == "1")
        #expect(defaults("read", domain, "autohide-delay") == "1000")

        try pipe.fileHandleForWriting.close()   // App „stirbt“
        watchdog.waitUntilExit()

        #expect(defaults("read", domain, "autohide") == "0")
        #expect(defaults("read", domain, "autohide-delay").isEmpty)
        _ = defaults("delete", domain)
    }

    @Test("Wächter ignoriert TERM und stellt trotzdem erst beim Pipe-Ende her")
    func ignoresTerm() throws {
        _ = defaults("delete", domain)
        let watchdog = Process()
        watchdog.executableURL = URL(filePath: "/bin/sh")
        watchdog.arguments = ["-c", SystemDockGuard.watchdogScript(domain: domain, originals: ["autohide": .bool(true)], restart: "true")]
        let pipe = Pipe()
        watchdog.standardInput = pipe
        try watchdog.run()
        Thread.sleep(forTimeInterval: 0.2)
        watchdog.terminate()
        Thread.sleep(forTimeInterval: 0.2)
        #expect(watchdog.isRunning)
        try pipe.fileHandleForWriting.close()
        watchdog.waitUntilExit()
        #expect(defaults("read", domain, "autohide") == "1")
        _ = defaults("delete", domain)
    }
}
