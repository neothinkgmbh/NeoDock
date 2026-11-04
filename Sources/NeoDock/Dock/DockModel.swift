import Foundation
import Observation

/// Welche Karte über einem Widget aufklappt.
enum CardKind: Equatable {
    case sessions, focus, calendar, calculator, clipboard, colors, password, note, volume
    case folder(URL)

    /// Karten mit Texteingabe werden Key-Window (ohne die App zu aktivieren).
    var needsKeyboard: Bool {
        switch self {
        case .calculator, .note: true
        default: false
        }
    }
}

/// Zusätzliche Breite der vergrößerten App-Reihe. Nur zwei kleine Hüllen lesen sie (Glas-Hintergrund
/// und Verschiebung von Widgets/Stapeln) — so rechnet SwiftUI beim Überfahren sonst nichts neu.
@Observable
final class MagnifyState {
    private(set) var extra: CGFloat = 0

    func setExtra(_ value: CGFloat) {
        if abs(value - extra) >= 0.25 || (value == 0 && extra != 0) { extra = value }
    }
}

/// Zustand der Leiste, den Views und Fenster-Controller teilen.
@Observable
final class DockModel {
    let settings: DockSettings
    let apps: AppsProvider
    let sessions: SessionStore
    let focus: FocusService
    let clipboard = ClipboardService()
    let colors = ColorService()
    let notes = NoteStore()
    let calendar = CalendarService()
    let volume = VolumeService()
    let keepAwake = KeepAwakeService()
    let magnify = MagnifyState()
    let trash = TrashMonitor()
    let badges = BadgeMonitor()
    let attention = AttentionMonitor()

    /// Die AppKit-App-Reihe — Prüfschalter setzen den nachgespielten Zeiger direkt dort,
    /// ohne SwiftUI (so wie die echte Maus über den Display-Link).
    @ObservationIgnored weak var appsRowView: AppsRowView?
    /// Apps mit Icon in der Leiste, die Aufmerksamkeit wollen. Apps ohne Icon zählen nicht.
    var attentionKeys: Set<String> { attention.keys.intersection(apps.apps.map(\.key)) }
    var edge: DockEdge { settings.dockEdge }
    /// Länge der Leiste in Ruhe (ohne Vergrößerung), vom Layout gemessen: Breite unten, Höhe an der Seite.
    var barLength: CGFloat = 0
    /// Icongröße der App-Reihe; schrumpft, wenn die Leiste sonst breiter als der Bildschirm wäre.
    var iconSize: CGFloat
    /// Icongröße, mit der `barLength` gemessen wurde.
    @ObservationIgnored var measuredIcon: CGFloat = 0
    var widgetPage = 0
    var battery: BatteryStatus? = Battery.read()
    var storage: StorageReader.Status? = StorageReader.read()

    @ObservationIgnored var onLayoutNeeded: (() -> Void)?
    /// Halten: Karte öffnen (bleibt offen, wenn sie es schon ist).
    @ObservationIgnored var onOpenCard: ((CardKind, CGFloat) -> Void)?
    /// Klick: dieselbe Karte schließt, eine andere ersetzt sie (Umschalten wie im macOS-Dock).
    @ObservationIgnored var onToggleCard: ((CardKind, CGFloat) -> Void)?
    /// Klick auf ein App-Icon oder eine schnelle Widget-Aktion: offene Karte schließen.
    @ObservationIgnored var onCloseCard: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored var onEditWidgets: (() -> Void)?
    @ObservationIgnored var onSystemDockSettingChanged: (() -> Void)?
    @ObservationIgnored var panelFrame: () -> CGRect = { .zero }
    @ObservationIgnored private var slowTask: Task<Void, Never>?

    init(settings: DockSettings) {
        self.settings = settings
        sessions = SessionStore(settings: settings)
        apps = AppsProvider(settings: settings)
        focus = FocusService(minutes: settings.focusMinutes)
        calendar.lookahead = TimeInterval(settings.calendarHours * 3600)
        iconSize = CGFloat(settings.maxIconSize)
    }

    /// Widgets schrumpfen mit den Icons (kleiner Bildschirm), wachsen aber nicht über ihre Normalgröße.
    var widgetScale: CGFloat { min(1, max(DockMetrics.minWidgetScale, iconSize / DockMetrics.icon)) }
    var barDepth: CGFloat { max(iconSize, DockMetrics.icon * widgetScale) + DockMetrics.padding * 2 }
    /// Maß quer zur Leiste: Reichweite vergrößerter Icons, ohne ihr Namensschild.
    var iconReach: CGFloat { barDepth + iconSize * CGFloat(settings.effectiveScale - 1) }
    /// Tiefe des Fensters: die Leiste plus Platz für vergrößerte Icons und ihr Namensschild.
    var panelDepth: CGFloat { iconReach + (edge.isVertical ? DockMetrics.sideLabelRoom : DockMetrics.labelRoom) }

    /// Angezeigte Widgets, in Seiten aufgeteilt; Widgets ohne Datenquelle fallen weg.
    var pages: [[WidgetKind]] {
        let visible = settings.enabledWidgets.filter { kind in
            switch kind {
            case .battery: battery != nil
            case .volume: volume.isAvailable
            case .storage: storage != nil
            default: true
            }
        }
        let size = max(1, settings.widgetsPerPage)
        return stride(from: 0, to: visible.count, by: size).map { Array(visible[$0..<min($0 + size, visible.count)]) }
    }

    var currentPage: [WidgetKind] {
        let pages = pages
        guard !pages.isEmpty else { return [] }
        return pages[min(widgetPage, pages.count - 1)]
    }

    func nextPage() {
        let count = pages.count
        guard count > 1 else { return }
        widgetPage = (min(widgetPage, count - 1) + 1) % count
    }

    func start() {
        apps.start()
        sessions.start()
        clipboard.start()
        calendar.start()
        volume.start()
        trash.start()
        badges.start()
        attention.start()
        slowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: DockMetrics.batteryInterval)
                let battery = Battery.read(), storage = StorageReader.read()
                if self?.battery != battery { self?.battery = battery }
                if self?.storage != storage { self?.storage = storage }
            }
        }
    }
}
