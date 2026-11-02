import NeoDockKit
import SwiftUI

/// Kleine „Gesichter“ links in den Widget-Kacheln — zeigen den Wert, statt ihn nur zu schreiben
/// (wie Komplikationen auf der Apple Watch). Alle 32 × 32 pt.
enum FaceMetrics {
    static let size: CGFloat = 32
    static let ring: CGFloat = 4
    static let corner: CGFloat = 9
    static let glyph: CGFloat = 15
}

/// Fortschrittsring mit Symbol in der Mitte (Fokus, Akku, Speicher, Lautstärke).
struct RingFace: View {
    let progress: Double
    let tint: Color
    let symbol: String
    /// Kurzwert im Ring (z. B. Restminuten, Prozent) — nur bei „Nur Symbole“, sonst das Symbol.
    var label: String?
    @Environment(\.widgetStyle) private var style

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: FaceMetrics.ring)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: FaceMetrics.ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            if style == .iconOnly, let label {
                Text(label)
                    .font(.system(size: FaceMetrics.glyph * 0.72, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, FaceMetrics.ring)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: FaceMetrics.glyph * 0.8, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .padding(FaceMetrics.ring / 2)
        .frame(width: FaceMetrics.size, height: FaceMetrics.size)
    }
}

/// Farbiges Plättchen mit Symbol (Rechner, Ablage, Passwort, Notiz, Wach halten …).
struct GlyphFace: View {
    let symbol: String
    let tint: Color
    var glowing = false

    var body: some View {
        RoundedRectangle(cornerRadius: FaceMetrics.corner)
            .fill(tint.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: FaceMetrics.glyph, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: glowing ? tint.opacity(0.8) : .clear, radius: glowing ? 6 : 0)
            .frame(width: FaceMetrics.size, height: FaceMetrics.size)
    }
}

/// Kalenderblatt wie das Kalender-Icon: roter Wochentag-Streifen, Tageszahl.
struct CalendarFace: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                .background(.red)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(maxHeight: .infinity)
        }
        .frame(width: FaceMetrics.size, height: FaceMetrics.size)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: FaceMetrics.corner * 0.8))
    }
}

/// Kleine Analoguhr (Minutengenau — kein Sekundenzeiger, der dauerhaft neu zeichnen würde).
struct ClockFace: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.9)))
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minute = Double(parts.minute ?? 0), hour = Double((parts.hour ?? 0) % 12) + minute / 60
            func hand(_ angle: Double, _ length: CGFloat, _ width: CGFloat, _ color: Color) {
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + sin(angle) * length, y: c.y - cos(angle) * length))
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            for tick in 0..<12 {
                let a = Double(tick) / 12 * 2 * .pi
                var t = Path()
                t.move(to: CGPoint(x: c.x + sin(a) * r * 0.78, y: c.y - cos(a) * r * 0.78))
                t.addLine(to: CGPoint(x: c.x + sin(a) * r * 0.9, y: c.y - cos(a) * r * 0.9))
                context.stroke(t, with: .color(.secondary), lineWidth: 1)
            }
            hand(hour / 12 * 2 * .pi, r * 0.5, 2.5, Color(nsColor: .windowBackgroundColor))
            hand(minute / 60 * 2 * .pi, r * 0.75, 1.8, Color(nsColor: .windowBackgroundColor))
            hand(minute / 60 * 2 * .pi, r * 0.75, 0.01, .orange)
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(.orange)) // grid: ok Zeichenmaß im Canvas
        }
        .frame(width: FaceMetrics.size, height: FaceMetrics.size)
    }
}

/// App-Icon eines Tools, ersatzweise sein Symbol.
struct ToolIcon: View {
    let tool: AgentTool
    let size: CGFloat

    var body: some View {
        if let image = ToolIcons.icon(tool) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: tool.symbol).font(.system(size: size * 0.6)).frame(width: size, height: size)
        }
    }
}

/// Farbtupfer der zuletzt gewählten Farbe.
struct SwatchFace: View {
    let color: Color?

    var body: some View {
        Circle()
            .fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)))
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
            .frame(width: FaceMetrics.size - 4, height: FaceMetrics.size - 4)
            .frame(width: FaceMetrics.size, height: FaceMetrics.size)
    }
}
