import AppKit
import UniformTypeIdentifiers
import os

extension UTType {
    /// Ein Icon, das innerhalb der Leiste gezogen wird. Bewusst KEIN file-url: sonst würde der
    /// Finder beim Ablegen auf dem Schreibtisch die echte App verschieben.
    static let neoDockItem = UTType(exportedAs: "ai.neothink.neodock.item")
}

/// Dateien, die auf die Leiste gezogen werden: in einen Stapel-Ordner legen, in den Papierkorb,
/// oder mit einer App öffnen.
enum FileDrops {
    static let log = Logger(subsystem: "ai.neothink.neodock", category: "drop")

    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let collected = URLCollector()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collected.urls
            MainActor.assumeIsolated { completion(urls) }
        }
    }

    /// Wie im Finder: auf demselben Volume verschieben, sonst kopieren (⌥ erzwingt Kopieren).
    /// Vorhandenes wird nie überschrieben.
    static func place(_ urls: [URL], into folder: URL) {
        let forceCopy = NSEvent.modifierFlags.contains(.option)
        var failed = false
        for url in urls where url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
            let destination = folder.appending(path: url.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { failed = true; continue }
            do {
                if forceCopy || !sameVolume(url, folder) {
                    try FileManager.default.copyItem(at: url, to: destination)
                } else {
                    try FileManager.default.moveItem(at: url, to: destination)
                }
            } catch {
                failed = true
                log.error("Ablegen fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
        if failed { NSSound.beep() }
    }

    static func trash(_ urls: [URL]) {
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch {
                NSSound.beep()
                log.error("Papierkorb fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let va = try? a.resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let vb = try? b.resourceValues(forKeys: key).volumeIdentifier as? NSObject else { return false }
        return va.isEqual(vb)
    }
}

/// Sammelt URLs aus den Rückrufen der Item-Provider (laufen auf beliebigen Threads).
nonisolated private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
    var urls: [URL] { lock.withLock { storage } }
}
