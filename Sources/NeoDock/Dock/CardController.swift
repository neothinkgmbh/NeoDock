import AppKit
import SwiftUI

/// Die aufgeklappte Karte eines Widgets: ein eigenes Panel über der Leiste.
/// Ein Klick irgendwo außerhalb schließt sie.
final class CardController {
    private let panel: DockPanel
    private var monitors: [Any] = []
    /// Klicks in diesem Fenster (der Leiste) schließen die Karte nicht — die Leiste entscheidet selbst.
    weak var ignoredWindow: NSWindow?

    init(level: NSWindow.Level) {
        panel = DockPanel(level: level)
        panel.hasShadow = true
    }

    var isVisible: Bool { panel.isVisible }

    func show(_ content: some View, needsKeyboard: Bool, anchorX: CGFloat, bottom: CGFloat, screen: NSScreen?) {
        close()
        let host = FirstClickHostingView(rootView: AnyView(
            content
                .frame(width: DockMetrics.cardWidth)
                .frame(maxHeight: DockMetrics.cardMaxHeight)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DockMetrics.corner))
        ))
        let size = host.fittingSize
        let bounds = screen?.visibleFrame ?? .infinite
        let x = min(max(anchorX - size.width / 2, bounds.minX + Space.sm), bounds.maxX - size.width - Space.sm)
        panel.contentView = host
        panel.allowsKey = needsKeyboard
        panel.setFrame(NSRect(x: x, y: bottom, width: size.width, height: size.height).integral, display: true)
        if needsKeyboard { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        installMonitors()
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
