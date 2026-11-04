import AppKit
import SwiftUI

// NEODOCK_SNAPSHOT=<ordner> NeoDock
// NEODOCK_SNAPSHOT_CARDS=focus,calculator,folder … wählt die Karten (Vorgabe: sessions).
// Rendert die Leiste und die Karten als PNG in den Ordner (ohne
// Bildschirmaufnahme-Recht, direkt aus der View-Hierarchie) und läuft dann weiter.
enum Snapshot {
    static let directory = ProcessInfo.processInfo.environment["NEODOCK_SNAPSHOT"].map { URL(filePath: $0) }
    static let settle: Duration = .seconds(3)

    static func scheduleIfRequested(_ dock: DockController) {
        guard let directory else { return }
        Task {
            try? await Task.sleep(for: settle)
            // NEODOCK_SNAPSHOT_HOVER=<x>: Zeigerposition (Koordinaten der App-Reihe) für den Leisten-Snapshot.
            if let x = ProcessInfo.processInfo.environment["NEODOCK_SNAPSHOT_HOVER"].flatMap(Double.init) {
                dock.model.appsRowView?.simulatedPointer = x
                try? await Task.sleep(for: .milliseconds(500))
            }
            dock.snapshotDock(to: directory.appending(path: "dock.png"))
            let names = (ProcessInfo.processInfo.environment["NEODOCK_SNAPSHOT_CARDS"] ?? "sessions").split(separator: ",")
            for (name, tab) in [("settings", SettingsTab.widgets), ("settings-general", SettingsTab.general)] where names.contains(Substring(name)) {
                dock.openSettings(tab: tab)
                try? await Task.sleep(for: .seconds(1))
                dock.snapshotSettings(to: directory.appending(path: "\(name).png"))
            }
            for name in names {
                guard let kind = card(named: String(name)) else { continue }
                dock.openCard(kind, anchor: 0)
                try? await Task.sleep(for: .seconds(1))
                dock.snapshotCard(to: directory.appending(path: "card-\(name).png"))
            }
        }
    }

    static func rowViews(in view: NSView) -> [AppsRowView] {
        view.subviews.flatMap { ($0 as? AppsRowView).map { [$0] } ?? rowViews(in: $0) }
    }

    /// Eine Instanz für Prüfbilder fasst weder das macOS-Dock noch fremde Fenster an.
    static let isRequested = ProcessInfo.processInfo.environment["NEODOCK_SNAPSHOT"] != nil

    static func card(named name: String) -> CardKind? {
        switch name {
        case "sessions": .sessions
        case "focus": .focus
        case "calendar": .calendar
        case "calculator": .calculator
        case "clipboard": .clipboard
        case "colors": .colors
        case "password": .password
        case "note": .note
        case "volume": .volume
        case "folder": .folder(URL.downloadsDirectory)
        case "applications": .folder(URL(filePath: "/Applications"))
        default: nil
        }
    }

    static func write(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Die App-Reihe besteht aus Core-Animation-Ebenen, die cacheDisplay nicht zeichnet.
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            for row in rowViews(in: view) {
                let origin = row.convert(CGPoint.zero, to: view)
                ctx.cgContext.saveGState()
                ctx.cgContext.scaleBy(x: CGFloat(rep.pixelsWide) / view.bounds.width, y: CGFloat(rep.pixelsHigh) / view.bounds.height)
                ctx.cgContext.translateBy(x: origin.x, y: view.isFlipped ? view.bounds.height - origin.y - row.bounds.height : origin.y)
                row.layer?.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// NEODOCK_HOVER_BENCH=1: spielt ein Überfahren der Leiste nach (setzt nur die Zeigerposition im
// Modell, bewegt nie den echten Mauszeiger), z. B. um währenddessen CPU oder `sample` zu messen.
enum HoverBench {
    static let isRequested = ProcessInfo.processInfo.environment["NEODOCK_HOVER_BENCH"] == "1"

    static func run(_ model: DockModel) {
        guard isRequested else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            AppsRowView.stats = (0, 0, 0)
            let start = Date()
            var steps = 0
            for x in stride(from: 0, to: Double(model.barLength), by: 12) {
                model.appsRowView?.simulatedPointer = x
                steps += 1
                try? await Task.sleep(for: .milliseconds(16))
            }
            model.appsRowView?.simulatedPointer = nil
            let elapsed = Date().timeIntervalSince(start)
            let stats = AppsRowView.stats
            NSLog("NeoDock HOVER_BENCH: Bilder=\(stats.frames) verpasst=\(stats.missed) längste Arbeit=\(String(format: "%.2f", stats.maxWorkMs)) ms; \(steps) Schritte, Dauer=\(String(format: "%.2f", elapsed)) s (Soll ≈ \(String(format: "%.2f", Double(steps) * 0.016)) s)")
        }
    }
}
