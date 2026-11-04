import Foundation
import NeoDockKit
import os

/// Blendet das macOS-Dock aus, solange NeoDock läuft und die Einstellung an ist.
/// Wiederherstellung: der Wächter aus `SystemDockGuard` hängt an einer Pipe zu diesem Prozess.
final class SystemDockHider {
    private var watchdog: Process?
    private var pipe: Pipe?
    private let defaults = UserDefaults.standard
    private static let pendingKey = "systemDock.pendingOriginals"
    private static let log = Logger(subsystem: "ai.neothink.neodock", category: "systemdock")

    var isActive: Bool { watchdog?.isRunning == true }

    /// Gibt die Dock-Fläche frei: Das geht nur über die private Funktion, also ruft der Wächter NeoDock selbst auf.
    private static var cleanup: [String] {
        Bundle.main.executablePath.map { ["\(SystemDockGuard.shellQuoted($0)) \(DockReservation.releaseArgument)"] } ?? []
    }

    /// Beim Start: Ist von einem früheren Lauf noch eine Wiederherstellung offen (etwa weil der
    /// Wächter mit SIGKILL beendet wurde), wird sie jetzt nachgeholt.
    func recoverIfNeeded() {
        guard let stored = defaults.dictionary(forKey: Self.pendingKey) as? [String: String], !isActive else { return }
        let originals = stored.mapValues(Self.decode)
        run(SystemDockGuard.commands(domain: SystemDockGuard.domain, values: originals) + Self.cleanup + ["/usr/bin/killall Dock"])
        defaults.removeObject(forKey: Self.pendingKey)
        Self.log.info("Systemdock aus früherem Lauf wiederhergestellt")
    }

    func enable() {
        guard !isActive else { return }
        let originals = SystemDockGuard.readOriginals()
        defaults.set(originals.mapValues(Self.encode), forKey: Self.pendingKey)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", SystemDockGuard.watchdogScript(originals: originals, cleanup: Self.cleanup)]
        let pipe = Pipe()
        process.standardInput = pipe
        do {
            try process.run()
        } catch {
            Self.log.error("Wächter startet nicht — Systemdock bleibt unverändert: \(error.localizedDescription, privacy: .public)")
            defaults.removeObject(forKey: Self.pendingKey)
            return
        }
        watchdog = process
        self.pipe = pipe
        run(SystemDockGuard.hideCommands() + ["/usr/bin/killall Dock"])
    }

    /// Pipe schließen: der Wächter stellt die Originale her und startet das Dock neu. Ist er selbst
    /// schon tot, tut das niemand mehr: dann hier nachholen, bevor die Sicherung gelöscht wird.
    func disable() {
        guard let pipe else { return }
        let hadWatchdog = isActive
        try? pipe.fileHandleForWriting.close()
        watchdog?.waitUntilExit()
        watchdog = nil
        self.pipe = nil
        if hadWatchdog {
            defaults.removeObject(forKey: Self.pendingKey)
        } else {
            recoverIfNeeded()
        }
    }

    private func run(_ commands: [String]) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", commands.joined(separator: "\n")]
        try? process.run()
        process.waitUntilExit()
    }

    private static func encode(_ value: SystemDockGuard.Original) -> String {
        switch value {
        case .bool(let b): "bool:\(b)"
        case .number(let n): "number:\(n)"
        case .absent: "absent"
        }
    }

    private static func decode(_ text: String) -> SystemDockGuard.Original {
        if text.hasPrefix("bool:") { return .bool(text.hasSuffix("true")) }
        if text.hasPrefix("number:"), let n = Double(text.dropFirst(7)) { return .number(n) }
        return .absent
    }
}
