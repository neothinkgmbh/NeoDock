import Foundation
import Observation
import ServiceManagement

/// Alle Widgets, die die Leiste kennt. Die Reihenfolge hier ist die Vorgabe.
enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case sessions, clock, focus, calendar, calculator, clipboard, colorPicker, password, note, volume, storage, keepAwake, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: "Agenten-Sitzungen"
        case .clock: "Uhr"
        case .focus: "Fokus-Timer"
        case .calendar: "Als Nächstes (Kalender)"
        case .calculator: "Rechner"
        case .clipboard: "Zwischenablage"
        case .colorPicker: "Farbwähler"
        case .password: "Passwort"
        case .note: "Notiz"
        case .volume: "Lautstärke"
        case .storage: "Speicher"
        case .keepAwake: "Wach halten"
        case .battery: "Akku"
        }
    }

    var symbol: String {
        switch self {
        case .sessions: "sparkles"
        case .clock: "clock"
        case .focus: "timer"
        case .calendar: "calendar"
        case .calculator: "plus.forwardslash.minus"
        case .clipboard: "doc.on.clipboard"
        case .colorPicker: "eyedropper"
        case .password: "key"
        case .note: "note.text"
        case .volume: "speaker.wave.2"
        case .storage: "internaldrive"
        case .keepAwake: "cup.and.saucer"
        case .battery: "battery.100"
        }
    }
}

/// Glas der Leiste: „Klar“ ist durchsichtiger und bricht das Licht stärker (wie das Dock in macOS Tahoe).
nonisolated enum GlassStyle: String, CaseIterable, Identifiable, Sendable {
    case clear, regular

    var id: String { rawValue }
    var title: String { self == .clear ? "Klar (mehr Liquid Glass)" : "Normal" }
}

/// Darstellung der Widgets: nur das Gesicht (Symbol) oder mit Wert und Beschriftung daneben.
nonisolated enum WidgetStyle: String, CaseIterable, Identifiable, Sendable {
    case iconOnly, withText

    var id: String { rawValue }
    var title: String { self == .iconOnly ? "Nur Symbole" : "Mit Text" }
}

/// Breite der Widget-Kacheln.
nonisolated enum WidgetWidth: String, CaseIterable, Identifiable, Sendable {
    case automatic, compact, normal, wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatisch (nach Inhalt)"
        case .compact: "Schmal"
        case .normal: "Normal"
        case .wide: "Breit"
        }
    }

    /// Feste Breite in Icon-Höhen; nil = nach Inhalt.
    var fixedFactor: CGFloat? {
        switch self {
        case .automatic: nil
        case .compact: 1.75
        case .normal: 2.25
        case .wide: 3
        }
    }
}

/// Einstellungen der Leiste, gespeichert in den UserDefaults der App.
@Observable
final class DockSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var enabledWidgets: [WidgetKind] { didSet { save(enabledWidgets.map(\.rawValue), "enabledWidgets") } }
    var widgetsPerPage: Int { didSet { save(widgetsPerPage, "widgetsPerPage") } }
    var maxIconSize: Double { didSet { save(maxIconSize, "maxIconSize") } }
    var magnification: Bool { didSet { save(magnification, "magnification") } }
    var magnificationScale: Double { didSet { save(magnificationScale, "magnificationScale") } }
    var showClaude: Bool { didSet { save(showClaude, "showClaude") } }
    var showCodex: Bool { didSet { save(showCodex, "showCodex") } }
    var codexHours: Double { didSet { save(codexHours, "codexHours") } }
    var passwordLength: Int { didSet { save(passwordLength, "passwordLength") } }
    var focusMinutes: Int { didSet { save(focusMinutes, "focusMinutes") } }
    var widgetWidth: WidgetWidth { didSet { save(widgetWidth.rawValue, "widgetWidth") } }
    var widgetStyle: WidgetStyle { didSet { save(widgetStyle.rawValue, "widgetStyle") } }
    var glassStyle: GlassStyle { didSet { save(glassStyle.rawValue, "glassStyle") } }
    /// Eigene Leiste nur zeigen, wenn der Zeiger an den unteren Rand fährt.
    var autohide: Bool { didSet { save(autohide, "autohide") } }
    /// macOS-Dock ausblenden, solange NeoDock läuft (mit Wiederherstellung).
    var hideSystemDock: Bool { didSet { save(hideSystemDock, "hideSystemDock") } }
    var calendarHours: Int { didSet { save(calendarHours, "calendarHours") } }
    /// Angeheftete Apps (Pfade), beim ersten Start einmal aus dem macOS-Dock übernommen.
    var pinnedApps: [String] { didSet { save(pinnedApps, "pinnedApps") } }
    /// Ordner-Stapel rechts in der Leiste (Pfade).
    var stackFolders: [String] { didSet { save(stackFolders, "stackFolders") } }

    static let iconRange: ClosedRange<Double> = 32...72
    static let scaleRange: ClosedRange<Double> = 1.2...2.0
    static let perPageRange: ClosedRange<Int> = 2...8
    static let codexHoursRange: ClosedRange<Double> = 1...24
    static let passwordRange: ClosedRange<Int> = 12...40
    static let focusChoices = [5, 15, 25, 50]
    static let calendarChoices = [12, 36, 72]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Fehlender Schlüssel = Vorgabe; eine leere Liste ist eine bewusste Wahl („keine Widgets“).
        enabledWidgets = defaults.stringArray(forKey: "enabledWidgets").map { $0.compactMap(WidgetKind.init(rawValue:)) }
            ?? WidgetKind.allCases
        widgetsPerPage = defaults.object(forKey: "widgetsPerPage") as? Int ?? 4
        maxIconSize = defaults.object(forKey: "maxIconSize") as? Double ?? 52
        magnification = defaults.object(forKey: "magnification") as? Bool ?? true
        magnificationScale = defaults.object(forKey: "magnificationScale") as? Double ?? 1.6
        showClaude = defaults.object(forKey: "showClaude") as? Bool ?? true
        showCodex = defaults.object(forKey: "showCodex") as? Bool ?? true
        codexHours = defaults.object(forKey: "codexHours") as? Double ?? 3
        passwordLength = defaults.object(forKey: "passwordLength") as? Int ?? 20
        focusMinutes = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        widgetWidth = defaults.string(forKey: "widgetWidth").flatMap(WidgetWidth.init(rawValue:)) ?? .automatic
        widgetStyle = defaults.string(forKey: "widgetStyle").flatMap(WidgetStyle.init(rawValue:)) ?? .iconOnly
        glassStyle = defaults.string(forKey: "glassStyle").flatMap(GlassStyle.init(rawValue:)) ?? .clear
        autohide = defaults.object(forKey: "autohide") as? Bool ?? false
        hideSystemDock = defaults.object(forKey: "hideSystemDock") as? Bool ?? false
        calendarHours = defaults.object(forKey: "calendarHours") as? Int ?? 36
        pinnedApps = defaults.stringArray(forKey: "pinnedApps") ?? AppsProvider.systemDockApps().map(\.path)
        // Beim ersten Start einmal die Ordner aus dem macOS-Dock übernehmen (nur gelesen).
        stackFolders = defaults.stringArray(forKey: "stackFolders") ?? Self.systemDockFolders()
        // didSet läuft im init nicht: die einmalige Übernahme aus dem macOS-Dock sofort festhalten,
        // sonst würde sie bei jedem Start neu gelesen (und ein aufgeräumtes macOS-Dock leerte NeoDock).
        if defaults.object(forKey: "pinnedApps") == nil { save(pinnedApps, "pinnedApps") }
        if defaults.object(forKey: "stackFolders") == nil { save(stackFolders, "stackFolders") }
    }

    func addStack(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !stackFolders.contains(path) else { return }
        stackFolders.append(path)
    }

    func removeStack(_ path: String) { stackFolders.removeAll { $0 == path } }

    func isPinned(_ url: URL) -> Bool { pinnedApps.contains(AppsProvider.key(url)) }

    func setPinned(_ url: URL, _ pinned: Bool) {
        let key = AppsProvider.key(url)
        if pinned, !pinnedApps.contains(key) { pinnedApps.append(key) }
        if !pinned { pinnedApps.removeAll { $0 == key } }
    }

    /// Ein Ordner — aber kein Paket (.app, .rtfd, .photoslibrary …), das der Finder als Datei zeigt.
    nonisolated static func isPlainFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    static func systemDockFolders() -> [String] {
        let fallback = [URL.downloadsDirectory.path]
        guard let tiles = CFPreferencesCopyAppValue("persistent-others" as CFString, "com.apple.dock" as CFString)
            as? [[String: Any]] else { return fallback }
        let paths: [String] = tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String else { return nil }
            let url = string.hasPrefix("file://") ? URL(string: string) : URL(filePath: string)
            guard let url, isPlainFolder(url) else { return nil }
            return url.standardizedFileURL.path
        }
        return paths.isEmpty ? fallback : paths
    }

    /// Wirksame Vergrößerung: 1 heißt aus.
    var effectiveScale: Double { magnification ? magnificationScale : 1 }

    func isEnabled(_ kind: WidgetKind) -> Bool { enabledWidgets.contains(kind) }

    /// Alle Widgets in Anzeigereihenfolge: eingeschaltete zuerst, dann die übrigen.
    var orderedWidgets: [WidgetKind] { enabledWidgets + WidgetKind.allCases.filter { !isEnabled($0) } }

    func resetWidgets() {
        enabledWidgets = WidgetKind.allCases
        widgetsPerPage = 4
        widgetWidth = .automatic
    }

    func setEnabled(_ kind: WidgetKind, _ on: Bool) {
        if on, !isEnabled(kind) {
            // An der Stelle der Vorgabe-Reihenfolge einsortieren.
            let order = WidgetKind.allCases
            let index = enabledWidgets.firstIndex { order.firstIndex(of: $0)! > order.firstIndex(of: kind)! } ?? enabledWidgets.count
            enabledWidgets.insert(kind, at: index)
        } else if !on {
            enabledWidgets.removeAll { $0 == kind }
        }
    }

    // Beim Anmelden starten: Zustand liegt bei macOS, nicht in den UserDefaults.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("NeoDock: Anmeldeobjekt konnte nicht geändert werden: \(error.localizedDescription)")
            }
        }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
