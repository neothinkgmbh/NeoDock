import AppKit
import ApplicationServices
import CoreGraphics
import NeoDockKit
import os

/// Meldet die Fläche der Leiste als Dock-Fläche. Das macOS-Dock überschreibt sie, sobald sich seine
/// Breite ändert (jeder App-Start), deshalb wird im Takt nachgesetzt. Sie überlebt das Ende von
/// NeoDock und einen Dock-Neustart, deshalb gibt sie der Wächter frei (`releaseArgument`).
/// Die Funktionen sind privat: Fehlen sie in einer künftigen macOS-Version, entfällt nur diese Funktion.
final class DockReservation {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias GetRect = @convention(c) (Int32, UnsafeMutablePointer<CGRect>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias SetRect = @convention(c) (Int32, CGRect, Int32) -> Int32

    /// Der Wert, mit dem auch das macOS-Dock seine Fläche meldet (gemessen).
    private static let reason: Int32 = 5
    /// Startargument von NeoDock: nur die Fläche freigeben und enden.
    nonisolated static let releaseArgument = "--release-dock-area"
    private static let interval: Duration = .seconds(1)
    private static let log = Logger(subsystem: "ai.neothink.neodock", category: "reservation")

    private let connection: Int32
    private let getRect: GetRect?
    private let setRect: SetRect?
    private var wanted: CGRect?
    private var isReserved = false
    private var task: Task<Void, Never>?

    init() {
        let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(sky, name).map { unsafeBitCast($0, to: type) }
        }
        connection = load("SLSMainConnectionID", as: MainConnection.self)?() ?? 0
        getRect = load("SLSGetDockRectWithReason", as: GetRect.self)
        setRect = load("SLSSetDockRectWithReason", as: SetRect.self)
        if getRect == nil || setRect == nil { Self.log.notice("Dock-Fläche nicht setzbar, Fenster richten sich nicht nach der Leiste") }
    }

    func reserve(_ area: CGRect) {
        guard area != wanted else { return }
        wanted = area
        isReserved = true
        enforce()
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.enforce()
            }
        }
    }

    /// Gibt den Platz frei (`free` hat die Tiefe 0).
    func release(_ free: CGRect) {
        guard isReserved else { return }
        stop()
        write(free)
    }

    /// Der Aufruf des Wächters: Der Hauptbildschirm genügt, die Einstellungen sind hier egal.
    func releaseNow() {
        write(DockArea.free(screen: CGDisplayBounds(CGMainDisplayID())))
    }

    /// Nur den Takt beenden. Freigegeben wird beim Abschalten des Wächters.
    func stop() {
        task?.cancel()
        task = nil
        wanted = nil
        isReserved = false
    }

    private func enforce() {
        guard let wanted, let getRect else { return }
        var current = CGRect.zero
        var reason: Int32 = 0
        if getRect(connection, &current, &reason) == 0, current != wanted { write(wanted) }
    }

    private func write(_ area: CGRect) {
        guard let setRect else { return }
        let result = setRect(connection, area, Self.reason)
        if result != 0 { Self.log.notice("Dock-Fläche abgelehnt: \(result)") }
    }
}

/// Kürzt offene Fenster, die in die Leiste ragen. Einmalig: Macht jemand ein Fenster danach von Hand
/// größer, bleibt es so, wie beim macOS-Dock.
nonisolated enum WindowFitter {
    private static let timeout: Float = 0.2
    private static let standardWindow = "AXStandardWindow"

    @MainActor static func fit(above area: CGRect, screen: CGRect) {
        let own = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
            .map(\.processIdentifier)
        Task.detached(priority: .utility) {
            for pid in pids { fitWindows(of: pid, above: area, screen: screen) }
        }
    }

    private static func fitWindows(of pid: pid_t, above area: CGRect, screen: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        for window in value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            AXUIElementSetMessagingTimeout(window, timeout)
            guard value(window, kAXSubroleAttribute) as? String == standardWindow,
                  value(window, kAXMinimizedAttribute) as? Bool != true,
                  value(window, "AXFullScreen") as? Bool != true,
                  let frame = frame(of: window), screen.contains(CGPoint(x: frame.midX, y: frame.midY)),
                  let fitted = DockArea.fitted(frame, above: area, minimum: DockMetrics.minFittedWindow),
                  var size = Optional(fitted.size), let value = AXValueCreate(.cgSize, &size) else { continue }
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
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
