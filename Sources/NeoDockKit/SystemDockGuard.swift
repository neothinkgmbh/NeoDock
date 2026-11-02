import Foundation

/// Blendet das macOS-Dock aus (Autohide mit sehr langer Verzögerung) und stellt die ursprünglichen
/// Werte absturzsicher wieder her: ein Wächter-Shellprozess blockiert auf einer Pipe zur App.
/// Endet die Pipe — App beendet, abgestürzt oder abgeschossen —, schreibt er die Originale zurück.
public enum SystemDockGuard {
    public enum Original: Equatable, Sendable {
        case bool(Bool), number(Double), absent
    }

    public static let domain = "com.apple.dock"
    public static let hiddenDelay: Double = 1000
    /// Die Schlüssel, die NeoDock ändert — und nur diese stellt der Wächter wieder her.
    public static let keys = ["autohide", "autohide-delay"]

    public static func readOriginals(domain: String = domain) -> [String: Original] {
        Dictionary(uniqueKeysWithValues: keys.map { key in
            let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
            if let number = value as? NSNumber {
                return (key, CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue))
            }
            return (key, .absent)
        })
    }

    /// `defaults`-Aufrufe, die einen Zustand herstellen. Werte sind typisiert, nie freier Text.
    public static func commands(domain: String, values: [String: Original]) -> [String] {
        values.keys.sorted().map { key in
            switch values[key]! {
            case .bool(let b): "/usr/bin/defaults write \(domain) \(key) -bool \(b ? "true" : "false")"
            case .number(let n): "/usr/bin/defaults write \(domain) \(key) -float \(n)"
            case .absent: "/usr/bin/defaults delete \(domain) \(key) 2>/dev/null"
            }
        }
    }

    public static func hideCommands(domain: String = domain) -> [String] {
        commands(domain: domain, values: ["autohide": .bool(true), "autohide-delay": .number(hiddenDelay)])
    }

    /// Shell-Skript des Wächters. `restart` startet das Dock neu (im Test: `true`).
    public static func watchdogScript(domain: String = domain, originals: [String: Original],
                                      restart: String = "/usr/bin/killall Dock") -> String {
        precondition(domain.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }, "unsichere Domäne")
        return (["trap '' INT HUP TERM", "read -r _"] + commands(domain: domain, values: originals) + [restart])
            .joined(separator: "\n")
    }
}
