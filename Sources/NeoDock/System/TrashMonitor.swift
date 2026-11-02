import AppKit
import Observation
import os

/// Ob etwas im Papierkorb liegt. ~/.Trash ist von macOS geschützt: zuerst direkt lesen, und wenn
/// macOS das verweigert, den Finder fragen (einmalige Abfrage „Finder steuern“).
@Observable
final class TrashMonitor {
    private(set) var isFull = false
    @ObservationIgnored private var task: Task<Void, Never>?
    static let interval: Duration = .seconds(3)
    /// Über den Finder (eigener osascript-Prozess je Abfrage) deutlich seltener.
    static let finderInterval: Duration = .seconds(15)
    /// Ob ~/.Trash direkt lesbar ist — einmal beim Start geprüft (macOS verweigert es meist).
    @ObservationIgnored private var canReadDirectly = FileManager.default.isReadableFile(atPath: TrashMonitor.trashPath)
        && (try? FileManager.default.contentsOfDirectory(atPath: TrashMonitor.trashPath)) != nil
    nonisolated static let trashPath = NSHomeDirectory() + "/.Trash"
    nonisolated private static let log = Logger(subsystem: "ai.neothink.neodock", category: "trash")

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.refresh()
                try? await Task.sleep(for: self.canReadDirectly ? Self.interval : Self.finderInterval)
            }
        }
    }

    /// Sofort neu prüfen (nach Ablegen auf dem Papierkorb oder Entleeren).
    func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.refresh()
        }
    }

    private func refresh() async {
        let direct = canReadDirectly
        let full = await Task.detached(priority: .utility) { Self.readIsFull(direct: direct) }.value
        if let full, isFull != full { isFull = full }
    }

    nonisolated static func readIsFull(direct: Bool) -> Bool? {
        if direct, let items = try? FileManager.default.contentsOfDirectory(atPath: trashPath) {
            return items.contains { $0 != ".DS_Store" && $0 != ".localized" }
        }
        return finderCount().map { $0 > 0 }
    }

    nonisolated static func finderCount() -> Int? {
        let output = osascript("tell application \"Finder\" to count items of trash")
        return output.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Papierkorb leeren — nach Rückfrage, weil es sich nicht rückgängig machen lässt.
    func emptyAfterConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Papierkorb endgültig entleeren?"
        alert.informativeText = "Die Objekte im Papierkorb werden sofort gelöscht. Das kann nicht widerrufen werden."
        alert.addButton(withTitle: "Entleeren")
        alert.addButton(withTitle: "Abbrechen")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task.detached(priority: .userInitiated) {
            if Self.osascript("tell application \"Finder\" to empty trash") == nil {
                Self.log.error("Papierkorb leeren fehlgeschlagen (Finder-Steuerung nicht erlaubt?)")
            }
        }
        refreshSoon()
    }

    nonisolated private static func osascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
