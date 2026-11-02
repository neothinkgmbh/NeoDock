import AppKit
import ApplicationServices
import Observation

/// Kennzahlen der App-Icons (ungelesene Mails usw.). Das macOS-Dock läuft auch ausgeblendet weiter
/// und trägt sie je Eintrag als `AXStatusLabel` — gelesen über die Bedienungshilfen-Schnittstelle,
/// nur lesend. Braucht einmalig die Bedienungshilfen-Freigabe für NeoDock.
@Observable
final class BadgeMonitor {
    /// App-Pfad (wie `DockApp.key`) → Kennzahl.
    private(set) var labels: [String: String] = [:]
    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored private var task: Task<Void, Never>?
    static let interval: Duration = .seconds(2)
    static let promptedKey = "accessibilityPromptShown"
    /// Hängt das Dock, wartet die Abfrage höchstens so lange.
    nonisolated static let messagingTimeout: Float = 0.5
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    /// Prüfschalter NEODOCK_TEST_BADGE="/System/Applications/Mail.app=3": gibt eine Kennzahl vor.
    static let testBadges: [String: String] = {
        guard let spec = ProcessInfo.processInfo.environment["NEODOCK_TEST_BADGE"],
              let eq = spec.lastIndex(of: "=") else { return [:] }
        return [String(spec[..<eq]): String(spec[spec.index(after: eq)...])]
    }()

    func start() {
        // Systemabfrage nur einmal überhaupt — danach zeigen die Einstellungen den Stand und öffnen
        // auf Wunsch die passende Systemeinstellung.
        if !isTrusted, !UserDefaults.standard.bool(forKey: Self.promptedKey) {
            UserDefaults.standard.set(true, forKey: Self.promptedKey)
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            isTrusted = AXIsProcessTrustedWithOptions(options)
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let trusted = AXIsProcessTrusted()
                var fresh = trusted ? await Task.detached(priority: .utility) { Self.read() }.value : [:]
                fresh.merge(Self.testBadges) { real, _ in real }
                if self?.isTrusted != trusted { self?.isTrusted = trusted }
                if self?.labels != fresh { self?.labels = fresh }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    nonisolated static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var result: [String: String] = [:]
        for list in children(app) {
            for item in children(list) {
                guard let label = value(item, "AXStatusLabel") as? String, !label.isEmpty,
                      let url = value(item, kAXURLAttribute) as? URL else { continue }
                result[AppsProvider.key(url)] = label
            }
        }
        return result
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    nonisolated private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
}
