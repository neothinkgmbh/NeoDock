import AppKit
import NeoDockKit
import SwiftUI

/// Rahmenloses, nicht aktivierendes Panel über dem Systemdock, auf allen Spaces.
final class DockPanel: NSPanel {
    /// Karten mit Texteingabe dürfen Key-Window werden; die Leiste nie.
    var allowsKey = false

    init(level: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Über dem Systemdock (dessen Ebene + 1), damit die Leiste nie darunter verschwindet.
    static let dockLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
}

/// Nimmt schon den ersten Klick an, obwohl das Panel nie Key-Window wird.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DockController {
    let settings = DockSettings()
    lazy var model = DockModel(settings: settings)
    private let panel = DockPanel(level: DockPanel.dockLevel)
    private lazy var card = CardController(level: DockPanel.dockLevel)
    private let settingsWindow = SettingsWindowController()
    private let systemDock = SystemDockHider()
    private let reservation = DockReservation()
    private let windowGuard = WindowGuard()
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    /// Bei Autohide: ist die Leiste gerade sichtbar?
    private var isRevealed = false
    private var hideTask: Task<Void, Never>?
    private var isLayoutScheduled = false

    func show() {
        let host = FirstClickHostingView(rootView: DockRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        model.onLayoutNeeded = { [weak self] in self?.scheduleLayout() }
        model.onOpenCard = { [weak self] kind, anchor in self?.openCard(kind, anchor: anchor) }
        model.onToggleCard = { [weak self] kind, anchor in self?.toggleCard(kind, anchor: anchor) }
        model.onCloseCard = { [weak self] in self?.card.close() }
        // Klicks in der Leiste schließen die Karte nicht pauschal — die Leiste entscheidet
        // (Umschalten, Ersetzen, Schließen); sonst öffnete ein zweiter Klick sie gleich wieder.
        card.ignoredWindow = panel
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onEditWidgets = { [weak self] in self?.openSettings(tab: .widgets) }
        model.onSystemDockSettingChanged = { [weak self] in self?.applySystemDockSetting() }
        model.panelFrame = { [weak self] in self?.panel.frame ?? .zero }
        if !Snapshot.isRequested { systemDock.recoverIfNeeded() }
        applySystemDockSetting()
        installMouseMonitors()
        model.start()
        layout()
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }
    }

    /// Der Bildschirm mit der Menüleiste — nicht NSScreen.main, das dem Tastaturfokus folgt.
    private var screen: NSScreen? { NSScreen.screens.first }

    /// Fenstergrößen nie innerhalb eines Layout-Durchlaufs setzen: die Anforderungen kommen aus
    /// SwiftUI-Geometrie-Aktionen mitten im Layout des Panels, und ein setFrame dort wirft in AppKit
    /// (`_postWindowNeedsLayout`, Absturz beim Ändern der Icongröße). Gesammelt, einmal danach.
    func scheduleLayout() {
        guard !isLayoutScheduled else { return }
        isLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutScheduled = false
            self.layout()
        }
    }

    func layout() {
        guard let screen else { return }
        // Prüfschalter NEODOCK_MAX_WIDTH=<pt>: so tun, als wäre der Bildschirm nur so breit.
        var visible = screen.visibleFrame
        if let simulated = Self.simulatedWidth { visible = visible.insetBy(dx: max(0, (visible.width - simulated) / 2), dy: 0) }
        let edge = settings.dockEdge
        let available = edge.isVertical ? visible.height : visible.width
        fitIcons(into: available * DockMetrics.maxScreenShare)
        let reserve = model.iconSize * CGFloat(settings.effectiveScale - 1) * DockMetrics.reserveIcons
        let length = min(max(model.barLength, DockMetrics.icon) + reserve, available)
        // Will eine App Aufmerksamkeit, fährt die Leiste hoch, sonst bliebe das Hüpfen unsichtbar.
        // Das zählt als normales Einblenden: Am Ende entscheidet `mouseMoved` wie sonst auch, ob sie
        // wegfährt, und lässt sie stehen, wenn der Zeiger darauf liegt oder eine Karte offen ist.
        let wantsAttention = !model.attentionKeys.isEmpty
        if settings.autohide, wantsAttention { isRevealed = true }
        if hadAttention, !wantsAttention { mouseMoved() }
        hadAttention = wantsAttention
        let shown = !settings.autohide || isRevealed
        let depth = model.panelDepth, gap = DockMetrics.bottomGap, bounds = screen.frame
        let frame: NSRect = switch edge {
        case .bottom:
            NSRect(x: visible.midX - length / 2, y: shown ? bounds.minY + gap : bounds.minY - depth, width: length, height: depth).integral
        case .left:
            NSRect(x: shown ? bounds.minX + gap : bounds.minX - depth, y: visible.midY - length / 2, width: depth, height: length).integral
        case .right:
            NSRect(x: shown ? bounds.maxX - gap - depth : bounds.maxX, y: visible.midY - length / 2, width: depth, height: length).integral
        }
        updateReservation(on: screen)
        // Hinter der Kante kann ein weiterer Monitor liegen: Dort stünde die verborgene Leiste sichtbar.
        // `ignoresMouseEvents` der Leiste nie setzen, auch nicht auf false: Dann nimmt das ganze Fenster
        // Klicks an, statt sie an durchsichtigen Stellen durchzulassen (gemessen). Unsichtbar genügt.
        let coversNeighbour = !shown && NSScreen.screens.contains { $0 != screen && $0.frame.intersects(frame) }
        let alpha: CGFloat = coversNeighbour ? 0 : 1
        guard frame != panel.frame else {
            panel.alphaValue = alpha
            return
        }
        if panel.frame.width == frame.width, panel.frame.height == frame.height {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DockMetrics.slideDuration
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = alpha
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.alphaValue = alpha
        }
    }

    /// Wie das macOS-Dock: Eine dauerhaft sichtbare Leiste unten belegt ihre Fläche, Zoomen, Kacheln und
    /// neue Fenster bleiben davor. Nur bei ausgeblendetem Dock: Sonst führt es seine Fläche selbst,
    /// und nur dann gibt der Wächter sie nach einem Absturz wieder frei.
    private func updateReservation(on screen: NSScreen) {
        let length = model.barLength
        guard settings.dockEdge == .bottom, settings.hideSystemDock, systemDock.isActive, !settings.autohide, length > 0 else {
            reservation.release(DockArea.free(screen: screen.frame))
            windowGuard.stop()
            return
        }
        let depth = DockMetrics.bottomGap + model.barDepth + Space.xs
        let area = DockArea.reserved(screen: screen.frame, length: length, depth: depth)
        reservation.reserve(area)
        windowGuard.update(area: area, screen: screen.frame)
    }

    // MARK: Autohide — die Leiste fährt aus, wenn der Zeiger ihren Bildschirmrand berührt.

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) { mouseMonitors.append(local) }
    }

    private var hadAttention = false

    private func mouseMoved() {
        guard settings.autohide, let screen else { return }
        let location = NSEvent.mouseLocation, bounds = screen.frame
        let edge = settings.dockEdge
        // An der Seite zählen beide Achsen: Links neben dem Bildschirm kann ein zweiter Monitor liegen.
        let onScreen = location.x >= bounds.minX && location.x <= bounds.maxX
            && (!edge.isVertical || (location.y >= bounds.minY && location.y <= bounds.maxY))
        let atEdge = switch edge {
        case .bottom: location.y <= bounds.minY + DockMetrics.revealEdge
        case .left: location.x <= bounds.minX + DockMetrics.revealEdge
        case .right: location.x >= bounds.maxX - DockMetrics.revealEdge
        }
        // An der Seite zählt die Reichweite der Icons: Das Fenster ist des Namensschilds wegen breit.
        let reach = model.iconReach + DockMetrics.hideMargin
        let isAway = switch edge {
        case .bottom: location.y > panel.frame.maxY + DockMetrics.hideMargin
        case .left: location.x > panel.frame.minX + reach
        case .right: location.x < panel.frame.maxX - reach
        }
        if !isRevealed, onScreen, atEdge {
            hideTask?.cancel()
            isRevealed = true
            layout()
        } else if isRevealed, isAway || !onScreen {
            guard hideTask == nil, !card.isVisible else { return }
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: DockMetrics.hideDelay)
                guard let self, !Task.isCancelled else { return }
                self.hideTask = nil
                self.isRevealed = false
                self.layout()
            }
        } else if isRevealed {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    // MARK: Systemdock

    func applySystemDockSetting() {
        guard !Snapshot.isRequested else { return }
        if settings.hideSystemDock {
            systemDock.enable()
        } else {
            // Vor `disable`: Der Wächter gibt die Fläche frei, der Takt darf sie nicht zurückholen.
            windowGuard.stop()
            reservation.stop()
            systemDock.disable()
        }
        scheduleLayout()
    }

    /// Beim regulären Beenden: Pipe schließen, der Wächter stellt das Dock wieder her.
    func shutdown() {
        windowGuard.stop()
        reservation.stop()
        systemDock.disable()
        model.attention.stop()
    }

    /// Wie das macOS-Dock: passt die Leiste nicht auf den Bildschirm, wird ALLES kleiner — Icons,
    /// Widgets, Stapel. Die Breite wächst monoton mit der Icongröße (Breite = a·Größe + b, b ≥ 0),
    /// daher nähert sich die Verhältnisrechnung dem Fixpunkt von einer Seite und pendelt nicht.
    /// Gerechnet wird mit der Größe, zu der die Breite gemessen wurde.
    static let simulatedWidth = ProcessInfo.processInfo.environment["NEODOCK_MAX_WIDTH"].flatMap(Double.init).map { CGFloat($0) }

    private func fitIcons(into maxWidth: CGFloat) {
        guard model.barLength > 0, model.measuredIcon > 0 else { return }
        // Sicherung gegen Pendeln (Rundungsstufen in Textbreiten): war die Leiste bei einer Größe zu
        // breit, wird sie nicht wieder so groß, solange sich an Inhalt und Platz nichts ändert.
        let inputs = [maxWidth, CGFloat(model.apps.apps.count), CGFloat(settings.stackFolders.count),
                      CGFloat(model.currentPage.count), CGFloat(model.badges.minimized.count), CGFloat(settings.maxIconSize)]
        if inputs != fitInputs { fitInputs = inputs; tooWideAt = nil }
        if model.barLength > maxWidth { tooWideAt = min(tooWideAt ?? .infinity, model.measuredIcon) }
        var fitting = (model.measuredIcon * maxWidth / model.barLength).rounded(.down)
        if let tooWideAt { fitting = min(fitting, tooWideAt - 1) }
        let size = min(CGFloat(settings.maxIconSize), max(DockMetrics.minIcon, fitting))
        if abs(size - model.iconSize) >= 1 { model.iconSize = size }
    }

    private var fitInputs: [CGFloat] = []
    private var tooWideAt: CGFloat?

    /// Prüfschalter NEODOCK_LOG_ICONS=1: Mitte jedes App-Icons in Bildschirmkoordinaten (Ursprung
    /// oben links, wie CGEvent) — für nachgestellte Ziehvorgänge.
    func logIconCenters() {
        guard !settings.dockEdge.isVertical, let screen = panel.screen ?? self.screen else { return }
        let size = model.iconSize, step = size + DockMetrics.iconSpacing
        let barLeft = panel.frame.midX - model.barLength / 2
        for (i, app) in model.apps.apps.enumerated() {
            let x = barLeft + DockMetrics.padding + CGFloat(i) * step + size / 2
            let y = screen.frame.maxY - (panel.frame.minY + DockMetrics.padding + size / 2)
            NSLog("NeoDock ICON \(app.name)|\(Int(x))|\(Int(y))")
        }
        // Stapel und Papierkorb rechts (in Ruhe): von der rechten Kante der Leiste nach innen.
        let barRight = panel.frame.midX + model.barLength / 2 - DockMetrics.padding - Space.xxs
        let items = model.settings.stackFolders.map { URL(filePath: $0).lastPathComponent } + ["Papierkorb"]
        for (i, name) in items.reversed().enumerated() {
            let x = barRight - size / 2 - CGFloat(i) * (size + DockMetrics.stackSpacing)
            let y = screen.frame.maxY - (panel.frame.minY + DockMetrics.padding + Space.xxs + size / 2)
            NSLog("NeoDock STACK \(name)|\(Int(x))|\(Int(y))")
        }
    }

    func snapshotDock(to url: URL) { Snapshot.write(panel.contentView, to: url) }
    func snapshotCard(to url: URL) { card.snapshot(to: url) }
    func snapshotSettings(to url: URL) { Snapshot.write(settingsWindow.contentView, to: url) }

    func toggleSessionsCard() {
        if card.isVisible { card.close(); return }
        openCard(.sessions, anchor: (settings.dockEdge.isVertical ? panel.frame.height : panel.frame.width) / 2)
    }

    private var openKind: CardKind?

    func toggleCard(_ kind: CardKind, anchor: CGFloat) {
        if card.isVisible, openKind == kind { card.close() } else { openCard(kind, anchor: anchor) }
    }

    /// `anchor`: Mitte der Kachel entlang der Leiste, in Fensterkoordinaten (y von oben).
    func openCard(_ kind: CardKind, anchor: CGFloat) {
        if card.isVisible, openKind == kind { return }
        openKind = kind
        let bar = panel.frame, depth = model.barDepth, edge = settings.dockEdge
        card.show(CardContent(kind: kind, model: model, close: { [weak self] in self?.card.close() }),
                  needsKeyboard: kind.needsKeyboard, origin: { size in
            switch edge {
            case .bottom: NSPoint(x: bar.minX + anchor - size.width / 2, y: bar.minY + depth + Space.sm)
            case .left: NSPoint(x: bar.minX + depth + Space.sm, y: bar.maxY - anchor - size.height / 2)
            case .right: NSPoint(x: bar.maxX - depth - Space.sm - size.width, y: bar.maxY - anchor - size.height / 2)
            }
        }, screen: panel.screen ?? screen)
    }

    func openSettings(tab: SettingsTab = .general) {
        card.close()
        settingsWindow.show(settings: settings, model: model, tab: tab)
    }
}
