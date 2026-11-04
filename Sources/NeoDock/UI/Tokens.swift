import NeoDockKit
import SwiftUI

/// Abstände auf dem 4-pt-Raster.
nonisolated enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

/// Maße der Leiste. Die Vergrößerung verändert das Layout nicht, nur Skalierung
/// und Versatz — deshalb reicht eine feste Reserve in Breite und Höhe.
nonisolated enum DockMetrics {
    static let icon: CGFloat = 52
    /// Untergrenze wie beim Systemdock.
    static let minIcon: CGFloat = 16
    static let minWidgetScale: CGFloat = 0.6
    static let tileValueSize: CGFloat = 15
    static let tileCaptionSize: CGFloat = 10
    /// „Nur Symbole“: Gesicht etwas größer in der quadratischen Kachel.
    static let iconOnlyFaceScale: CGFloat = 1.25
    static let maxScreenShare: CGFloat = 0.94
    static let iconSpacing: CGFloat = 8
    static let reachInIcons: Double = 3
    static let padding: CGFloat = 8
    static let corner: CGFloat = 24
    static let bottomGap: CGFloat = 8
    /// Fenster, die in die Leiste ragen, werden nur gekürzt, wenn so viel von ihnen bleibt.
    static let minFittedWindow: CGFloat = 200
    /// Automatische Widgetbreite: zwischen quadratisch und 3,5 Icon-Höhen, in Stufen, damit die
    /// Leiste nicht bei jeder Textänderung (neue Minute) ein Stück wandert.
    static let widgetMinWidth: CGFloat = icon
    static let widgetMaxWidth: CGFloat = icon * 3.5
    static let widgetWidthStep: CGFloat = 24
    static let tileCorner: CGFloat = 14
    static let runDot: CGFloat = 4
    /// Platz über vergrößerten Icons für das Namensschild.
    static let labelRoom: CGFloat = 32
    /// Dasselbe für die Leiste an der Seite: Das Schild steht neben dem Icon und ist breiter als hoch.
    static let sideLabelRoom: CGFloat = 180
    /// Größte zusätzliche Breite der vergrößerten Reihe, in Icon-Wachstum (Glocke über ~5 Icons).
    static let reserveIcons: CGFloat = 4
    static let pagerWidth: CGFloat = 28
    static let stackSpacing: CGFloat = 8
    static let minimizedBadgeShare: CGFloat = 0.55
    static let cardWidth: CGFloat = 360
    static let cardMaxHeight: CGFloat = 440
    /// Liste und Raster der Stapel-Karte; alles darüber wird gescrollt.
    static let folderContentMaxHeight: CGFloat = 320
    static let folderRowHeight: CGFloat = 36
    static let folderGridColumns = 4
    static let folderCellHeight: CGFloat = 84
    static let folderGridIcon: CGFloat = 48
    static let longPress: Double = 0.4
    static let pollInterval: Duration = .seconds(2)
    static let batteryInterval: Duration = .seconds(60)
    static let launchTimeout: Duration = .seconds(10)
    static let flashDuration: Duration = .seconds(2)
    static let slideDuration: Double = 0.2
    /// Ein-/Ausblenden der Vergrößerung (Zeitkonstante); der Zeiger selbst wird ohne Verzögerung verfolgt.
    static let magnifyEase: Double = 0.07
    static let dragThreshold: CGFloat = 4
    static let pressedShade: CGFloat = 0.3
    static let dropTargetScale: CGFloat = 1.15
    static let revealEdge: CGFloat = 2
    static let hideMargin: CGFloat = 24
    static let hideDelay: Duration = .milliseconds(500)
    /// Zeitraster, in dem nach dem Loslassen geprüft wird, wo ein gezogenes Icon gelandet ist.
    static let dragPoll: Duration = .milliseconds(50)
    /// Wie weit über der Leiste ein Icon losgelassen werden muss, damit es entfernt wird.
    static let removeDistance: CGFloat = 40
    /// Hüpfhöhe in Icon-Größen und Dauer eines Hüpfers (hoch + runter).
    static let bounceHeight: CGFloat = 0.5
    static let bouncePeriod: Double = 0.55
    static let bounceUp: Double = 0.2
    static let bounceDown: Double = 0.25
    static let bouncePause: Duration = .milliseconds(80)
    static let pressedBrightness: Double = -0.3
    static let pressedTileScale: CGFloat = 0.96
}

extension SessionState {
    var color: Color {
        switch self {
        case .needsYou: .orange
        case .working: .green
        case .ready: .secondary
        }
    }
}

extension AgentTool {
    var symbol: String { self == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right" }
}
