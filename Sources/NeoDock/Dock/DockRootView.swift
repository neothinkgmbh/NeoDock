import AppKit
import NeoDockKit
import SwiftUI

struct DockRootView: View {
    @Bindable var model: DockModel

    var body: some View {
        // Die Breite gehört zu genau dieser Icongröße — beide zusammen melden, sonst rechnet die
        // Größenanpassung mit einer veralteten Breite und pendelt zwischen zwei Größen.
        let renderedIcon = model.iconSize
        DockBar(model: model)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                model.barWidth = width
                model.measuredIcon = renderedIcon
                model.onLayoutNeeded?()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onChange(of: model.settings.maxIconSize) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.effectiveScale) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.autohide) { model.onLayoutNeeded?() }
            .onChange(of: model.attentionKeys) { model.onLayoutNeeded?() }
            .onChange(of: model.settings.hideSystemDock) { model.onSystemDockSettingChanged?() }
    }
}

/// Apps | Widgets | Stapel auf einer Glasfläche. Die App-Reihe ist eine AppKit-View mit
/// Core-Animation-Ebenen (`AppsRowView`); dieser Body wird beim Überfahren NICHT neu berechnet.
struct DockBar: View {
    @Bindable var model: DockModel

    var body: some View {
        let count = CGFloat(model.apps.apps.count)
        let restWidth = max(0, count * (model.iconSize + DockMetrics.iconSpacing) - DockMetrics.iconSpacing)
        let reserve = model.iconSize * CGFloat(model.settings.effectiveScale - 1) * DockMetrics.reserveIcons
        HStack(alignment: .bottom, spacing: DockMetrics.iconSpacing) {
            // Platzhalter in Ruhegröße fürs Layout; die View darüber ist breiter und höher, damit
            // vergrößerte Icons Klicks bekommen (sie lässt Ereignisse außerhalb der Icons durch).
            Color.clear
                .frame(width: restWidth, height: model.iconSize)
                .overlay(alignment: .bottom) {
                    AppsRow(model: model)
                        .frame(width: restWidth + reserve, height: model.panelHeight - DockMetrics.padding)
                }

            FollowsMagnification(state: model.magnify) {
                HStack(alignment: .bottom, spacing: DockMetrics.iconSpacing) {
                    BarDivider(scale: model.widgetScale)
                    WidgetsRow(model: model)
                    BarDivider(scale: model.widgetScale)
                    StacksRow(model: model)
                }
            }
        }
        .padding(DockMetrics.padding)
        .background { MagnifiedGlass(state: model.magnify, style: model.settings.glassStyle) }
        .frame(height: model.panelHeight, alignment: .bottom)
        .contextMenu {
            Button("Widgets bearbeiten …") { model.onEditWidgets?() }
            Toggle("Vergrößerung", isOn: Bindable(model.settings).magnification)
            Button("Einstellungen …") { model.onOpenSettings?() }
            Divider()
            Button("NeoDock beenden") { NSApp.terminate(nil) }
        }
    }
}

/// Widgets und Stapel weichen der vergrößerten App-Reihe nach rechts aus. Nur diese Hülle liest
/// die Zusatzbreite — ihr Inhalt wird dabei nicht neu berechnet.
struct FollowsMagnification<Content: View>: View {
    let state: MagnifyState
    @ViewBuilder let content: Content

    var body: some View {
        content.offset(x: state.extra / 2) // grid: ok folgt der Vergrößerung
    }
}

/// Glasfläche der Leiste, wächst um die Zusatzbreite der Vergrößerung mit.
struct MagnifiedGlass: View {
    let state: MagnifyState
    let style: GlassStyle

    var body: some View {
        Color.clear
            .glassEffect(style == .clear ? .clear : .regular, in: RoundedRectangle(cornerRadius: DockMetrics.corner))
            .padding(.horizontal, -state.extra / 2)
    }
}

struct BarDivider: View {
    var scale: CGFloat = 1

    var body: some View {
        Divider()
            .frame(height: DockMetrics.icon * 0.7 * scale)
            .padding(.horizontal, Space.xs)
            .padding(.bottom, DockMetrics.icon * 0.15 * scale)
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
