import AppKit
import NeoDockKit
import Observation

struct DockApp: Identifiable, Equatable {
    let url: URL
    let name: String
    let icon: NSImage
    var isRunning: Bool
    /// Vergleichsschlüssel (Pfad), einmal berechnet — wird pro Bild gebraucht.
    let key: String
    var id: URL { url }
}

/// Die Apps der Leiste: Finder, die im macOS-Dock angehefteten Apps (nur gelesen aus
/// `com.apple.dock` / persistent-apps), danach alle übrigen laufenden Apps.
@Observable
final class AppsProvider {
    private(set) var apps: [DockApp] = []
    /// Das Icon, das gerade innerhalb der Leiste gezogen wird.
    private(set) var dragging: DockApp?
    /// Apps, die gestartet wurden, aber noch nicht laufen — ihr Icon hüpft.
    private(set) var launching: Set<String> = []
    @ObservationIgnored private var iconCache: [URL: NSImage] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    static let finderURL = URL(filePath: "/System/Library/CoreServices/Finder.app")
    @ObservationIgnored private let settings: DockSettings

    init(settings: DockSettings) { self.settings = settings }

    func start() {
        reload()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
    }

    func reload() {
        // Nur echte Apps: Pfad existiert und ist kein Hilfsprogramm in einer anderen App (sonst erscheint
        // ein leeres Phantom-Icon, das sich nicht öffnen lässt — z. B. während eines App-Updates).
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let url = app.bundleURL else { return false }
            return FileManager.default.fileExists(atPath: url.path) && !url.path.contains(".app/Contents/")
        }
        let runningKeys = Set(running.compactMap { $0.bundleURL.map(Self.key) })
        let pinnedURLs = settings.pinnedApps.map { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        var urls = [Self.finderURL] + pinnedURLs.filter { Self.key($0) != Self.key(Self.finderURL) }
        let pinned = Set(urls.map(Self.key))
        urls += running.compactMap(\.bundleURL).filter { !pinned.contains(Self.key($0)) }
        let next = urls.map { url in
            DockApp(url: url, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                    icon: icon(for: url), isRunning: runningKeys.contains(Self.key(url)), key: Self.key(url))
        }
        if next != apps { apps = next }
        let stillLaunching = launching.subtracting(runningKeys)
        if stillLaunching != launching { launching = stillLaunching }
    }

    func isLaunching(_ app: DockApp) -> Bool { !launching.isEmpty && launching.contains(app.key) }

    func open(_ app: DockApp) {
        if !app.isRunning {
            let key = Self.key(app.url)
            launching.insert(key)
            Task { [weak self] in
                try? await Task.sleep(for: DockMetrics.launchTimeout)
                self?.launching.remove(key)
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
    }

    private func icon(for url: URL) -> NSImage {
        if let cached = iconCache[url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url] = image
        return image
    }

    /// Vergleichsschlüssel: Dock-Einträge tragen einen abschließenden Schrägstrich, laufende Apps nicht.
    nonisolated static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    // MARK: Ziehen innerhalb der Leiste (AppKit meldet Beginn und Ende)

    func setDragging(_ app: DockApp?) { dragging = app }

    /// Aus der Leiste gezogen: nicht mehr behalten (Finder bleibt immer).
    func removeFromDock(_ app: DockApp) {
        guard app.key != Self.key(Self.finderURL) else { return }
        settings.setPinned(app.url, false)
        reload()
    }

    /// Live-Umsortieren: das gezogene Icon nimmt den Platz des Ziels ein.
    func move(_ dragged: DockApp, toward target: DockApp) {
        let next = DockOrder.moving(Self.key(dragged.url), toward: Self.key(target.url), pinned: settings.pinnedApps,
                                    visible: apps.map { Self.key($0.url) }, fixedFirst: Self.key(Self.finderURL))
        guard next != settings.pinnedApps else { return }
        settings.pinnedApps = next
        reload()
    }

    /// App aus dem Finder an einer Stelle anheften.
    func pin(_ url: URL, before target: DockApp?) {
        settings.pinnedApps = DockOrder.inserting(Self.key(url), before: target.map { Self.key($0.url) },
                                                  pinned: settings.pinnedApps)
        reload()
    }

    func openFiles(_ urls: [URL], with app: DockApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: configuration)
    }

    func runningApp(_ app: DockApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL.map(Self.key) == Self.key(app.url) }
    }

    func togglePinned(_ app: DockApp) {
        settings.setPinned(app.url, !settings.isPinned(app.url))
        reload()
    }

    /// Angeheftete Apps aus dem macOS-Dock (`com.apple.dock` / persistent-apps), nur gelesen.
    static func systemDockApps() -> [URL] {
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString)
            as? [[String: Any]] else { return [] }
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String else { return nil }
            let url = string.hasPrefix("file://") ? URL(string: string) : URL(filePath: string)
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }
}
