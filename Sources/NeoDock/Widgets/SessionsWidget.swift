import NeoDockKit
import SwiftUI

/// Sitzungs-Widget: zeigt je Tool die Zahl der Sitzungen. Klick oder Halten öffnet die Liste; wer
/// wartet, steht dort oben. Der Klick springt bewusst nicht direkt zur wartenden Sitzung: Eine seit
/// Stunden offene Frage ließe die Liste sonst nie aufgehen.
struct SessionsWidget: View {
    let store: SessionStore
    let hold: (CGFloat) -> Void
    /// Klick: Liste umschalten (zweiter Klick schließt).
    let toggle: (CGFloat) -> Void
    @Environment(DockModel.self) private var model: DockModel?

    var body: some View {
        let toolStack = model?.edge.isVertical == true ? AnyLayout(VStackLayout(spacing: Space.sm)) : AnyLayout(HStackLayout(spacing: Space.sm))
        // Nur Symbole — je Tool sein App-Icon mit Zahl der Sitzungen; die Farbe der Zahl zeigt den
        // dringendsten Zustand. Spart Platz; Details zeigt die Liste.
        WidgetTile(caption: nil, hold: hold, tapAt: toggle,
                   tint: store.needsYou.isEmpty ? (store.working.isEmpty ? .gray : .green) : .orange,
                   isActive: !store.needsYou.isEmpty) {
            toolStack {
                if store.sessions.isEmpty {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
                } else {
                    ForEach(AgentTool.allCases, id: \.self) { tool in
                        let sessions = store.sessions.filter { $0.tool == tool }
                        if !sessions.isEmpty { ToolCountBadge(tool: tool, sessions: sessions) }
                    }
                }
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        guard !store.sessions.isEmpty else { return "Keine Agenten-Sitzungen" }
        let parts = [("arbeiten", store.working.count), ("warten auf dich", store.needsYou.count)]
            .filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
        return (parts.isEmpty ? "alle bereit" : parts.joined(separator: " · ")) + " — Klick: alle Sitzungen"
    }
}

/// App-Icon eines Tools mit der Zahl seiner Sitzungen; Farbe = dringendster Zustand.
struct ToolCountBadge: View {
    let tool: AgentTool
    let sessions: [AgentSession]
    @Environment(\.widgetScale) private var scale

    private var state: SessionState { sessions.map(\.state).min() ?? .ready }

    var body: some View {
        let size = FaceMetrics.size * scale
        ToolIcon(tool: tool, size: size)
            .overlay(alignment: .topTrailing) {
                Text("\(sessions.count)")
                    .font(.system(size: size * 0.36, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, size * 0.12)
                    .frame(minWidth: size * 0.5, minHeight: size * 0.5)
                    .background(Capsule().fill(state == .ready ? Color.gray : state.color))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)) // grid: ok Strichstärke, kein Abstand
                    .offset(x: size * 0.2, y: -size * 0.2) // grid: ok Plakette am Icon-Rand
                    .symbolEffect(.pulse, isActive: state == .working)
            }
            .padding(.trailing, size * 0.15)
            .help("\(tool.label): \(sessions.count) Sitzung(en)")
    }
}

extension AgentSession {
    /// Claude: der Projektordner ist aussagekräftiger als der Sitzungsname (im Home-Ordner der Name).
    /// Codex: der Thread-Name — Desktop-Threads liegen in automatisch benannten Ordnern.
    var displayName: String {
        tool == .codex || project == "~" || origin?.hasPrefix("claude-desktop") == true ? name : project
    }
}

struct SessionsCard: View {
    let store: SessionStore
    let onPick: (AgentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Agenten-Sitzungen").font(.headline)
                Spacer()
                Text("\(store.working.count) arbeiten · \(store.needsYou.count) warten")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.sessions.isEmpty {
                ContentUnavailableView("Keine Sitzungen", systemImage: "moon.zzz",
                                       description: Text("Weder Claude Code noch Codex laufen gerade."))
            } else {
                ScrollView {
                    VStack(spacing: Space.xxs) {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session) { onPick(session) }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(Space.lg)
    }
}

struct SessionRow: View {
    let session: AgentSession
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Circle().fill(session.state.color).frame(width: Space.sm, height: Space.sm)
                ToolIcon(tool: session.tool, size: Space.lg + Space.xs)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(session.displayName).font(.body.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                if let since = session.since {
                    TimelineView(.everyMinute) { _ in
                        Text(since.formatted(.relative(presentation: .named)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: Space.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(session.tool.label), \(session.name), \(session.state.label)")
    }

    private var subtitle: String {
        let label: String = switch session.origin {
        case ClaudeDesktopSessionSource.codeOrigin?: "Claude-App · Code"
        case ClaudeDesktopSessionSource.coworkOrigin?: "Claude-App · Cowork"
        default: session.tool.label
        }
        let isDesktop = session.origin?.hasPrefix("claude-desktop") == true
        let secondary: String? = switch session.tool {
        // Cowork arbeitet in einem internen Ordner der App („outputs“) — der sagt nichts aus.
        case .claude: isDesktop ? (session.origin == ClaudeDesktopSessionSource.codeOrigin ? session.project : nil)
                                : (session.project == "~" ? nil : session.name)
        case .codex: session.origin == CodexHost.cli.rawValue ? session.project : nil
        }
        return [label, secondary, session.detail ?? session.state.label].compactMap { $0 }.joined(separator: " · ")
    }
}
