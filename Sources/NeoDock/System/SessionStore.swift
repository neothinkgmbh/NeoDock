import AppKit
import Foundation
import NeoDockKit
import Observation

/// Fragt Claude- und Codex-Sitzungen im Takt ab. Datei- und SQLite-Zugriffe laufen
/// abseits des Main-Threads; nur das Ergebnis landet auf ihm.
@Observable
final class SessionStore {
    private(set) var sessions: [AgentSession] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let settings: DockSettings

    init(settings: DockSettings) { self.settings = settings }

    var needsYou: [AgentSession] { sessions.filter { $0.state == .needsYou } }
    var working: [AgentSession] { sessions.filter { $0.state == .working } }

    /// Die Sitzung, die ein Klick aufs Widget anspringt: zuerst wer wartet, dann wer arbeitet.
    var mostUrgent: AgentSession? { needsYou.first ?? working.first }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: DockMetrics.pollInterval)
            }
        }
    }

    func refresh() async {
        let runningHosts = Set([CodexHost.desktop, .vscode].filter(CodexHosts.isRunning))
        let claudeAppRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: ToolIcons.claudeAppID).isEmpty
        let showClaude = settings.showClaude, showCodex = settings.showCodex
        let hours = Self.codexWindowOverride ?? settings.codexHours
        let fresh = await Task.detached(priority: .utility) {
            var codex: [AgentSession] = []
            if showCodex {
                var source = CodexSessionSource()
                source.visibleWindow = hours * 3600
                codex = Self.liveCodex(source.sessions(), runningHosts: runningHosts)
            }
            let claude = showClaude ? ClaudeSessionSource().sessions() : []
            // Sitzungen der Claude-Desktop-App (Code-Bereich, Agentenmodus) — ohne die, die schon
            // als Claude-Code-Sitzung in der Registry stehen.
            let desktop = showClaude
                ? Self.desktopSource.sessions(isAppRunning: claudeAppRunning, knownCliIDs: Set(claude.map(\.id)))
                : []
            return (claude + desktop + codex).sortedByUrgency()
        }.value
        if fresh != sessions { sessions = fresh }
    }

    /// Codex-Threads ohne laufenden Prozess sind keine Sitzungen mehr: CLI-Threads brauchen einen
    /// codex-Prozess am Terminal im selben Ordner, App-Threads eine laufende Codex-/VS-Code-App.
    /// Prüfschalter: NEODOCK_CODEX_HOURS=<h> überschreibt das Codex-Zeitfenster der Einstellungen.
    nonisolated static let codexWindowOverride = ProcessInfo.processInfo.environment["NEODOCK_CODEX_HOURS"].flatMap(Double.init)

    /// Prüfschalter NEODOCK_DESKTOP_HOURS=<h>: Zeitfenster für Sitzungen der Claude-Desktop-App.
    nonisolated static let desktopSource: ClaudeDesktopSessionSource = {
        var source = ClaudeDesktopSessionSource()
        if let hours = ProcessInfo.processInfo.environment["NEODOCK_DESKTOP_HOURS"].flatMap(Double.init) {
            source.visibleWindow = hours * 3600
        }
        return source
    }()

    nonisolated static func liveCodex(_ sessions: [AgentSession], runningHosts: Set<CodexHost>) -> [AgentSession] {
        let cliFolders = Set(ProcessTable.codexCLIs().compactMap(\.cwd))
        return sessions.filter { session in
            switch CodexHost(rawValue: session.origin ?? "") {
            case .cli?: cliFolders.contains(session.cwd)
            case .desktop?: runningHosts.contains(.desktop)
            case .vscode?: runningHosts.contains(.vscode)
            case .exec?, .unknown?, nil: session.state != .ready
            }
        }
    }
}
