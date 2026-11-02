import Foundation

/// Reihenfolge der angehefteten Apps beim Umsortieren und Anheften. Schlüssel sind Pfade.
public enum DockOrder {
    /// Das gezogene Icon nimmt den Platz des Ziels ein; nach rechts gezogen landet es hinter ihm.
    /// `visible` ist die angezeigte Reihenfolge, `fixedFirst` (Finder) bleibt vorn.
    public static func moving(_ dragged: String, toward target: String, pinned: [String],
                              visible: [String], fixedFirst: String) -> [String] {
        guard dragged != target, dragged != fixedFirst else { return pinned }
        let movingRight = (visible.firstIndex(of: dragged) ?? 0) < (visible.firstIndex(of: target) ?? 0)
        var result = pinned.filter { $0 != dragged }
        if target == fixedFirst {
            result.insert(dragged, at: 0)
        } else if let i = result.firstIndex(of: target) {
            result.insert(dragged, at: movingRight ? i + 1 : i)
        } else {
            result.append(dragged)
        }
        return result
    }

    public static func inserting(_ key: String, before target: String?, pinned: [String]) -> [String] {
        var result = pinned.filter { $0 != key }
        if let target, let i = result.firstIndex(of: target) { result.insert(key, at: i) } else { result.append(key) }
        return result
    }
}
