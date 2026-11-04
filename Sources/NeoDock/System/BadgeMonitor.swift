import AppKit
import ApplicationServices
import Observation

/// Ein minimiertes Fenster, wie es das macOS-Dock führt.
nonisolated struct MinimizedWindow: Identifiable, Equatable, @unchecked Sendable {
    let title: String
    let element: AXUIElement
    /// Besitzer-App; nil, wenn sie sich nicht ermitteln ließ (das Dock nennt sie nicht).
    let appURL: URL?

    var id: CFHashCode { CFHash(element) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.appURL == rhs.appURL && CFEqual(lhs.element, rhs.element)
    }
}

/// Kennzahlen der App-Icons (ungelesene Mails usw.) und minimierte Fenster. Das macOS-Dock läuft
/// auch ausgeblendet weiter und führt beides je Eintrag — gelesen über die
/// Bedienungshilfen-Schnittstelle. Braucht einmalig die Bedienungshilfen-Freigabe für NeoDock.
@Observable
final class BadgeMonitor {
    /// App-Pfad (wie `DockApp.key`) → Kennzahl.
    private(set) var labels: [String: String] = [:]
    private(set) var minimized: [MinimizedWindow] = []
    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored private var task: Task<Void, Never>?
    static let interval: Duration = .seconds(2)
    static let promptedKey = "accessibilityPromptShown"
    /// Hängt das Dock, wartet die Abfrage höchstens so lange.
    nonisolated static let messagingTimeout: Float = 0.5
    /// Hängt eine App bei der Suche nach dem Fensterbesitzer, kommt die nächste dran.
    nonisolated static let ownerTimeout: Float = 0.2
    nonisolated static let minimizedSubrole = "AXMinimizedWindowDockItem"
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
                let known = self?.minimized ?? []
                let apps = Self.regularApps()
                var fresh = trusted ? await Task.detached(priority: .utility) { Self.read(known: known, apps: apps) }.value : Reading()
                fresh.labels.merge(Self.testBadges) { real, _ in real }
                if self?.isTrusted != trusted { self?.isTrusted = trusted }
                if self?.labels != fresh.labels { self?.labels = fresh.labels }
                if self?.minimized != fresh.minimized { self?.minimized = fresh.minimized }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Holt das Fenster zurück: derselbe Weg wie ein Klick im macOS-Dock.
    func restore(_ window: MinimizedWindow) {
        minimized.removeAll { $0 == window }
        Task.detached(priority: .userInitiated) {
            let result = AXUIElementPerformAction(window.element, kAXPressAction as CFString)
            if result != .success { NSLog("NeoDock: Fenster nicht zurückgeholt: \(result.rawValue)") }
        }
    }

    nonisolated struct Reading: Sendable {
        var labels: [String: String] = [:]
        var minimized: [MinimizedWindow] = []
    }

    private static func regularApps() -> [(pid: pid_t, url: URL)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let url = app.bundleURL else { return nil }
            return (app.processIdentifier, url)
        }
    }

    /// `known`: Für bekannte Fenster ist der Besitzer schon ermittelt, das Abfragen aller Apps entfällt.
    nonisolated static func read(known: [MinimizedWindow], apps: [(pid: pid_t, url: URL)]) -> Reading {
        var reading = Reading()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return reading }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        for list in children(app) {
            for item in children(list) {
                if value(item, kAXSubroleAttribute) as? String == minimizedSubrole {
                    guard let title = value(item, kAXTitleAttribute) as? String else { continue }
                    let appURL = known.first { CFEqual($0.element, item) }.map(\.appURL) ?? owner(of: title, in: apps)
                    reading.minimized.append(MinimizedWindow(title: title, element: item, appURL: appURL))
                } else if let label = value(item, "AXStatusLabel") as? String, !label.isEmpty,
                          let url = value(item, kAXURLAttribute) as? URL {
                    reading.labels[AppsProvider.key(url)] = label
                }
            }
        }
        return reading
    }

    nonisolated private static func owner(of title: String, in apps: [(pid: pid_t, url: URL)]) -> URL? {
        for app in apps {
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, ownerTimeout)
            let windows = value(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if windows.contains(where: { value($0, kAXMinimizedAttribute) as? Bool == true && value($0, kAXTitleAttribute) as? String == title }) {
                return app.url
            }
        }
        return nil
    }

    nonisolated private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    nonisolated private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
}
