import SwiftUI

/// Gemeinsame Form der Widgets: Wert groß, Beschriftung klein.
/// Klick = schnelle Aktion, Gedrückthalten = Karte aufklappen (mit der Mitte der Kachel als Anker).
struct WidgetTile<Value: View>: View {
    /// nil = ohne Beschriftung (reine Symbol-Kachel).
    let caption: String?
    var tap: () -> Void = {}
    var hold: ((CGFloat) -> Void)?
    /// Klick mit dem Anker der Kachel (statt `tap`), z. B. um eine Karte zu öffnen.
    var tapAt: ((CGFloat) -> Void)?
    /// Gesicht links (Ring, Plättchen, Kalenderblatt …) und Farbe des Schimmers.
    var face: AnyView?
    var tint: Color = .secondary
    /// Aktiv (Timer läuft, Wach halten an): der Schimmer leuchtet stärker.
    var isActive = false
    @ViewBuilder let value: Value
    @State private var isPressed = false
    @State private var anchor: CGFloat = 0
    @Environment(\.widgetWidth) private var width
    @Environment(\.widgetScale) private var scale
    @Environment(\.widgetStyle) private var style
    @Environment(DockModel.self) private var model: DockModel?

    private var isVertical: Bool { model?.edge.isVertical == true }

    var body: some View {
        let vertical = isVertical
        content
            .frame(minHeight: DockMetrics.icon * scale, maxHeight: vertical ? nil : DockMetrics.icon * scale)
            .background {
                RoundedRectangle(cornerRadius: DockMetrics.tileCorner * scale)
                    .fill(.quaternary.opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: DockMetrics.tileCorner * scale)
                            .fill(LinearGradient(colors: [tint.opacity(isActive ? 0.32 : 0.14), tint.opacity(isActive ? 0.12 : 0.04)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DockMetrics.tileCorner * scale)
                            .strokeBorder(.white.opacity(isActive ? 0.25 : 0.1), lineWidth: 1)
                    }
                    .animation(.easeOut(duration: 0.3), value: isActive)
            }
            .help(style == .iconOnly ? (caption ?? "") : "")
            .contentShape(RoundedRectangle(cornerRadius: DockMetrics.tileCorner * scale))
            .scaleEffect(isPressed ? DockMetrics.pressedTileScale : 1)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .onGeometryChange(for: CGFloat.self) { vertical ? $0.frame(in: .global).midY : $0.frame(in: .global).midX } action: { anchor = $0 }
            .onTapGesture {
                if let tapAt { tapAt(anchor) } else { model?.onCloseCard?(); tap() }
            }
            .onLongPressGesture(minimumDuration: DockMetrics.longPress, perform: { hold?(anchor) },
                                onPressingChanged: { isPressed = $0 })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    /// Nur Symbole: quadratische Kachel mit dem Gesicht, etwas größer. Mit Text: Gesicht + Wert + Beschriftung.
    @ViewBuilder private var content: some View {
        if style == .iconOnly, let face {
            face.scaleEffect(scale * DockMetrics.iconOnlyFaceScale)
                .frame(width: DockMetrics.icon * scale, height: DockMetrics.icon * scale)
        } else if isVertical {
            // Ohne Gesicht (Sitzungen): so breit wie die Leiste, die Höhe folgt dem Inhalt.
            value.padding(.vertical, Space.sm * scale).frame(width: DockMetrics.icon * scale)
        } else {
            textContent
        }
    }

    private var textContent: some View {
        QuantizedWidth(width: width, scale: scale) {
            HStack(spacing: Space.sm * scale) {
                if let face {
                    face.scaleEffect(scale)
                        .frame(width: FaceMetrics.size * scale, height: FaceMetrics.size * scale)
                }
                VStack(alignment: .leading, spacing: Space.xxs * scale) {
                    value
                        .font(.system(size: DockMetrics.tileValueSize * scale, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                    if let caption {
                        Text(caption)
                            .font(.system(size: DockMetrics.tileCaptionSize * scale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, (face == nil ? Space.md : Space.sm) * scale)
            .padding(.trailing, Space.md * scale)
        }
    }
}

/// Breite einer Kachel: fest (Einstellung) oder nach Inhalt, auf Stufen gerundet und begrenzt.
/// Zu langer Text wird gekürzt (lineLimit 1).
struct QuantizedWidth: Layout {
    let width: WidgetWidth
    var scale: CGFloat = 1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(.unspecified)
        let height = proposal.height ?? ideal.height
        if let factor = width.fixedFactor { return CGSize(width: DockMetrics.icon * factor * scale, height: height) }
        let step = DockMetrics.widgetWidthStep * scale
        let stepped = (ideal.width / step).rounded(.up) * step
        return CGSize(width: min(DockMetrics.widgetMaxWidth * scale, max(DockMetrics.widgetMinWidth * scale, stepped)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

extension EnvironmentValues {
    @Entry var widgetWidth: WidgetWidth = .automatic
    /// Maßstab der Widgets: folgt der Icongröße (kleiner Bildschirm → alles kleiner), 60–100 %.
    @Entry var widgetScale: CGFloat = 1
    @Entry var widgetStyle: WidgetStyle = .iconOnly
}

/// Die aktuelle Widget-Seite. Der Umschalter steht links: bei variabler Widgetbreite bleibt er so
/// beim Durchklicken unter dem Zeiger.
struct WidgetsRow: View {
    @Bindable var model: DockModel

    var body: some View {
        let pages = model.pages
        let page = model.currentPage
        let tileStack = model.edge.stack(spacing: DockMetrics.iconSpacing)
        tileStack {
            if pages.count > 1 {
                PagerButton(index: min(model.widgetPage, pages.count - 1), count: pages.count, vertical: model.edge.isVertical) {
                    withAnimation(.snappy) { model.nextPage() }
                }
            }
            ForEach(page) { kind in
                WidgetView(kind: kind, model: model)
                    .contextMenu {
                        Button("Widget entfernen") { model.settings.setEnabled(kind, false) }
                        Button("Widgets bearbeiten …") { model.onEditWidgets?() }
                    }
            }
        }
        .environment(\.widgetWidth, model.settings.widgetWidth)
        .environment(\.widgetScale, model.widgetScale)
        .environment(\.widgetStyle, model.edge.isVertical ? .iconOnly : model.settings.widgetStyle)
        .environment(model)
    }
}

struct PagerButton: View {
    let index: Int
    let count: Int
    let vertical: Bool
    let action: () -> Void
    @Environment(\.widgetScale) private var scale

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(systemName: vertical ? "chevron.up.chevron.down" : "chevron.left.chevron.right").font(.callout.weight(.semibold))
                HStack(spacing: Space.xxs) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle().fill(i == index ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: Space.xs, height: Space.xs)
                    }
                }
            }
            .frame(width: (vertical ? DockMetrics.icon : DockMetrics.pagerWidth) * scale,
                   height: (vertical ? DockMetrics.pagerWidth : DockMetrics.icon) * scale)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DockMetrics.tileCorner * scale))
            .contentShape(Rectangle())
        }
        .buttonStyle(DockPressStyle())
        .help("Nächste Widgets")
        .accessibilityLabel("Nächste Widgets, Seite \(index + 1) von \(count)")
    }
}
