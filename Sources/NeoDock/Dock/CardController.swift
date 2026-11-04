import AppKit
import SwiftUI

/// Die aufgeklappte Karte eines Widgets: ein eigenes Panel neben der Leiste.
/// Ein Klick irgendwo außerhalb schließt sie.
extension EnvironmentValues {
    /// Die Karte, in der eine Ansicht steht.
    @Entry var cardController: CardController?
}

final class CardController {
    private let panel: DockPanel
    private var monitors: [Any] = []
    private var placement: (host: NSView, origin: (NSSize) -> NSPoint, bounds: CGRect)?
    /// Klicks in diesem Fenster (der Leiste) schließen die Karte nicht — die Leiste entscheidet selbst.
    weak var ignoredWindow: NSWindow?

    init(level: NSWindow.Level) {
        panel = DockPanel(level: level)
        panel.hasShadow = true
    }

    var isVisible: Bool { panel.isVisible }

    /// `origin`: Lage der Karte zu ihrer Größe; der Bildschirmrand begrenzt sie.
    func show(_ content: some View, needsKeyboard: Bool, origin: @escaping (NSSize) -> NSPoint, screen: NSScreen?) {
        close()
        let host = FirstClickHostingView(rootView: AnyView(
            content
                .frame(width: DockMetrics.cardWidth)
                .frame(maxHeight: DockMetrics.cardMaxHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DockMetrics.corner))
                .environment(\.cardController, self)
        ))
        placement = (host, origin, screen?.visibleFrame ?? .infinite)
        panel.contentView = host
        panel.allowsKey = needsKeyboard
        refit()
        if needsKeyboard { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        installMonitors()
    }

    /// Größe aus dem Inhalt. Karten, die erst laden, rufen das danach noch einmal auf.
    func refit() {
        guard let placement else { return }
        let size = placement.host.fittingSize, bounds = placement.bounds
        let point = placement.origin(size)
        let x = min(max(point.x, bounds.minX + Space.sm), bounds.maxX - size.width - Space.sm)
        let y = min(max(point.y, bounds.minY + Space.sm), bounds.maxY - size.height - Space.sm)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height).integral, display: true)
    }

    func snapshot(to url: URL) { Snapshot.write(panel.contentView, to: url) }

    func close() {
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if event.window !== self?.panel, event.window !== self?.ignoredWindow { self?.close() }
            return event
        }) { monitors.append(local) }
    }
}
