import AppKit
import SwiftUI

// NeoDock — eine eigene Dockleiste mit Widgets, darunter ein Widget für laufende
// Claude-Code- und Codex-Sitzungen. Läuft als Hintergrund-App (LSUIElement) mit
// einem Menüleisten-Symbol zum Beenden.

@main
struct NeoDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("NeoDock", systemImage: "dock.rectangle") {
            Button("Agenten-Sitzungen zeigen") { delegate.dock.toggleSessionsCard() }
                .keyboardShortcut("s")
            Button("Einstellungen …") { delegate.dock.openSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("NeoDock beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let dock = DockController()

    func applicationWillTerminate(_ notification: Notification) { dock.shutdown() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock.show()
        Snapshot.scheduleIfRequested(dock)
        HoverBench.run(dock.model)
        if ProcessInfo.processInfo.environment["NEODOCK_LOG_ICONS"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(2))
                dock.logIconCenters()
            }
        }
        // Prüfschalter: NEODOCK_OPEN_SETTINGS=widgets öffnet die Einstellungen direkt.
        if ProcessInfo.processInfo.environment["NEODOCK_OPEN_SETTINGS"] == "widgets" {
            dock.openSettings(tab: .widgets)
            Task {
                try? await Task.sleep(for: .seconds(1))
                NSLog("NeoDock: Einstellungen key=\(NSApp.keyWindow?.title ?? "keins")")
            }
        }
    }
}
