import Foundation

/// Merkt sich je Datei ein aus ihrem Inhalt berechnetes Ergebnis, solange Größe und Änderungszeit
/// gleich bleiben. Die Sitzungsquellen laufen alle 2 s; ohne das zerlegen sie jedes Mal Hunderte
/// unveränderter Dateien neu. Für `compute` zählt nur der Dateiinhalt, nie die Uhrzeit. `nil` heißt
/// Lesefehler und wird nicht gemerkt: Die Datei einer wartenden Sitzung ändert sich nicht mehr, ein
/// gemerkter Fehler bliebe also für immer stehen.
public final class FileMemo<Value: Sendable>: @unchecked Sendable {
    private struct Stamp: Equatable {
        let size: Int64
        let seconds: Int
        let nanoseconds: Int
    }

    private var entries: [String: (stamp: Stamp, value: Value)] = [:]
    private let lock = NSLock()

    public init() {}

    public func value(for url: URL, compute: () -> Value?) -> Value? {
        let path = url.path
        guard let stamp = Self.stamp(of: path) else { return compute() }
        if let hit = lock.withLock({ entries[path] }), hit.stamp == stamp { return hit.value }
        guard let value = compute() else { return nil }
        lock.withLock {
            if entries.count >= fileMemoCapacity { entries.removeAll() }
            entries[path] = (stamp, value)
        }
        return value
    }

    private static func stamp(of path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Stamp(size: Int64(info.st_size), seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec)
    }
}

/// Obergrenze je Cache, damit er über Wochen Laufzeit nicht wächst.
private let fileMemoCapacity = 4096
