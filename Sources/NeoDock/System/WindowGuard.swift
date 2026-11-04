import AppKit
import ApplicationServices
import NeoDockKit

/// Hält Fenster vor der Leiste. Die angemeldete Dock-Fläche (`DockReservation`) wirkt nur auf neu
/// gestartete Apps: Laufende haben sie zwischengespeichert und bekommen von außen kein Signal, das
/// sendet allein das macOS-Dock (gemessen). Deshalb beobachtet dieser Wächter sie: Wächst ein Fenster
/// in die Leiste, etwa durch Zoomen, wird es gekürzt. Verschieben bleibt frei, wie beim macOS-Dock.
final class WindowGuard {
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Fenster, für die eine Prüfung ansteht: Live-Größenänderungen melden sich pro Bild.
    private var pending: Set<CFHashCode> = []
    private var area: CGRect?
    private var screen: CGRect = .zero
    private static let mousePoll: Duration = .milliseconds(30)
    private static let retryDelay: Duration = .seconds(2)
    /// Beim Wechsel in den Vollbildmodus meldet sich das Fenster, bevor es als Vollbild gilt.
    private static let settleDelay: Duration = .milliseconds(120)

    /// Beobachtet ab jetzt und kürzt einmal alle offenen Fenster.
    func update(area: CGRect, screen: CGRect) {
        let isFirst = self.area == nil
        self.area = area
        self.screen = screen
        guard isFirst else { return }
        Self.regularApps().forEach(observe)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { self?.observe(pid) } }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { self?.forget(pid) } }
            },
        ]
        WindowFitter.fit(above: area, screen: screen)
    }

    func stop() {
        guard area != nil else { return }
        area = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        observers.keys.forEach(forget)
    }

    private static func regularApps() -> [pid_t] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
            .map(\.processIdentifier)
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, area != nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let added = [kAXWindowResizedNotification, kAXWindowCreatedNotification].map {
            AXObserverAddNotification(observer, app, $0 as CFString, context)
        }
        // Eine App, die gerade erst startet, nimmt noch keine Beobachter an.
        guard added.contains(.success) else {
            Task { [weak self] in
                try? await Task.sleep(for: Self.retryDelay)
                self?.observeIfRunning(pid)
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func observeIfRunning(_ pid: pid_t) {
        guard NSRunningApplication(processIdentifier: pid) != nil else { return }
        observe(pid)
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private static let callback: AXObserverCallback = { _, element, _, context in
        guard let context else { return }
        let guardian = Unmanaged<WindowGuard>.fromOpaque(context).takeUnretainedValue()
        let window = FittedWindow(element: element)
        MainActor.assumeIsolated { guardian.windowChanged(window) }
    }

    /// Mit gedrückter Maustaste zieht jemand am Fenster: erst nach dem Loslassen kürzen.
    private func windowChanged(_ window: FittedWindow) {
        let key = CFHash(window.element)
        guard pending.insert(key).inserted else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            while NSEvent.pressedMouseButtons != 0 { try? await Task.sleep(for: Self.mousePoll) }
            guard let self else { return }
            self.pending.remove(key)
            guard let area = self.area else { return }
            let screen = self.screen
            await Task.detached(priority: .userInitiated) { WindowFitter.fit(window.element, above: area, screen: screen) }.value
        }
    }
}

/// AXUIElement ist threadsicher, nur nicht als Sendable markiert.
private nonisolated struct FittedWindow: @unchecked Sendable {
    let element: AXUIElement
}

/// Kürzt Fenster, die in die Leiste ragen.
nonisolated enum WindowFitter {
    private static let timeout: Float = 0.2
    private static let standardWindow = "AXStandardWindow"

    @MainActor static func fit(above area: CGRect, screen: CGRect) {
        let own = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
            .map(\.processIdentifier)
        Task.detached(priority: .utility) {
            for pid in pids {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, timeout)
                for window in value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                    fit(window, above: area, screen: screen)
                }
            }
        }
    }

    static func fit(_ window: AXUIElement, above area: CGRect, screen: CGRect) {
        AXUIElementSetMessagingTimeout(window, timeout)
        guard value(window, kAXSubroleAttribute) as? String == standardWindow,
              value(window, kAXMinimizedAttribute) as? Bool != true,
              value(window, "AXFullScreen") as? Bool != true,
              let frame = frame(of: window), screen.contains(CGPoint(x: frame.midX, y: frame.midY)),
              let fitted = DockArea.fitted(frame, above: area, minimum: DockMetrics.minFittedWindow),
              var size = Optional(fitted.size), let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = value(window, kAXPositionAttribute), let size = value(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
}
