import AppKit
import NeoDockKit
import SwiftUI

extension DockEdge {
    /// Woran die Leiste im Fenster anliegt.
    var alignment: Alignment {
        switch self {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// Stapel entlang der Leiste, an der Bildschirmkante ausgerichtet.
    func stack(spacing: CGFloat) -> AnyLayout {
        switch self {
        case .bottom: AnyLayout(HStackLayout(alignment: .bottom, spacing: spacing))
        case .left: AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        case .right: AnyLayout(VStackLayout(alignment: .trailing, spacing: spacing))
        }
    }
}

struct DockRootView: View {
    @Bindable var model: DockModel

    var body: some View {
        // Die Länge gehört zu genau dieser Icongröße — beide zusammen melden, sonst rechnet die
        // Größenanpassung mit einer veralteten Länge und pendelt zwischen zwei Größen.
        let renderedIcon = model.iconSize
        let vertical = model.edge.isVertical
        DockBar(model: model)
            .onGeometryChange(for: CGFloat.self) { vertical ? $0.size.height : $0.size.width } action: { length in
                model.barLength = length
                model.measuredIcon = renderedIcon
                model.onLayoutNeeded?()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.edge.alignment)
            .onChange(of: model.settings.maxIconSize) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.effectiveScale) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.autohide) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.dockEdge) { model.onLayoutNeeded?() }
            .onChange(of: model.attentionKeys) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.hideSystemDock) { model.onSystemDockSettingChanged?() }
    }
}

/// Apps | Widgets | Stapel auf einer Glasfläche. Die App-Reihe ist eine AppKit-View mit
/// Core-Animation-Ebenen (`AppsRowView`); dieser Body wird beim Überfahren NICHT neu berechnet.
struct DockBar: View {
    @Bindable var model: DockModel

    var body: some View {
        let edge = model.edge
        let vertical = edge.isVertical
        let count = CGFloat(model.apps.apps.count)
        let restLength = max(0, count * (model.iconSize + DockMetrics.iconSpacing) - DockMetrics.iconSpacing)
        let reserve = model.iconSize * CGFloat(model.settings.effectiveScale - 1) * DockMetrics.reserveIcons
        let rowLength = restLength + reserve
        let rowDepth = model.panelDepth - DockMetrics.padding
        let barStack = edge.stack(spacing: DockMetrics.iconSpacing)
        barStack {
            // Platzhalter in Ruhegröße fürs Layout; die View darüber ist größer, damit vergrößerte
            // Icons Klicks bekommen (sie lässt Ereignisse außerhalb der Icons durch).
            Color.clear
                .frame(width: vertical ? model.iconSize : restLength, height: vertical ? restLength : model.iconSize)
                .overlay(alignment: edge.alignment) {
                    AppsRow(model: model)
                        .frame(width: vertical ? rowDepth : rowLength, height: vertical ? rowLength : rowDepth)
                }

            FollowsMagnification(state: model.magnify, vertical: vertical) {
                barStack {
                    BarDivider(scale: model.widgetScale, vertical: vertical)
                    WidgetsRow(model: model)
                    BarDivider(scale: model.widgetScale, vertical: vertical)
                    StacksRow(model: model)
                }
            }
        }
        .padding(DockMetrics.padding)
        .background { MagnifiedGlass(state: model.magnify, style: model.settings.glassStyle, vertical: vertical) }
        .frame(width: vertical ? model.panelDepth : nil, height: vertical ? nil : model.panelDepth, alignment: edge.alignment)
        .contextMenu {
            Button("Widgets bearbeiten …") { model.onEditWidgets?() }
            Toggle("Vergrößerung", isOn: Bindable(model.settings).magnification)
            Picker("Position", selection: Bindable(model.settings).dockEdge) {
                ForEach(DockEdge.allCases) { Text($0.title).tag($0) }
            }
            Button("Einstellungen …") { model.onOpenSettings?() }
            Divider()
            Button("NeoDock beenden") { NSApp.terminate(nil) }
        }
    }
}

/// Widgets und Stapel weichen der vergrößerten App-Reihe aus. Nur diese Hülle liest die
/// Zusatzlänge — ihr Inhalt wird dabei nicht neu berechnet.
struct FollowsMagnification<Content: View>: View {
    let state: MagnifyState
    let vertical: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(x: vertical ? 0 : state.extra / 2, y: vertical ? state.extra / 2 : 0) // grid: ok folgt der Vergrößerung
    }
}

/// Glasfläche der Leiste, wächst um die Zusatzlänge der Vergrößerung mit.
struct MagnifiedGlass: View {
    let state: MagnifyState
    let style: GlassStyle
    let vertical: Bool

    var body: some View {
        Color.clear
            .glassEffect(style == .clear ? .clear : .regular, in: RoundedRectangle(cornerRadius: DockMetrics.corner))
            .padding(vertical ? .vertical : .horizontal, -state.extra / 2)
    }
}

struct BarDivider: View {
    var scale: CGFloat = 1
    var vertical = false

    var body: some View {
        let length = DockMetrics.icon * 0.7 * scale
        let inset = DockMetrics.icon * 0.15 * scale
        if vertical {
            Rectangle()
                .fill(.separator)
                .frame(width: length, height: 1)
                .padding(.vertical, Space.xs)
                .padding(.horizontal, inset)
        } else {
            Divider()
                .frame(height: length)
                .padding(.horizontal, Space.xs)
                .padding(.bottom, inset)
        }
    }
}

/// Dunkelt ab, solange die Maus gedrückt ist — wie im Systemdock (Stapel, Seitenumschalter).
struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? DockMetrics.pressedBrightness : 0)
            .contentShape(Rectangle())
    }
}
