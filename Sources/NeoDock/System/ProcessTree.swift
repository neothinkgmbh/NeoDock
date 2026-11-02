import AppKit
import NeoDockKit

/// Welche reguläre App (Terminal, iTerm, Ghostty, VS Code …) einen Prozess beherbergt.
enum ProcessTree {
    static let maxHops = 32

    /// Erste PID der Elternkette, die zu einer App mit Dock-Präsenz gehört.
    static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var current: pid_t? = pid
        for _ in 0..<maxHops {
            guard let p = current else { return nil }
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular { return app }
            current = ProcessTable.parent(of: p)
        }
        return nil
    }

    static func codexCLI(in cwd: String) -> pid_t? {
        ProcessTable.codexCLIs().first { $0.cwd == cwd }?.pid
    }
}
