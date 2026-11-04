# NeoDock

Eine eigene macOS-Dockleiste (Liquid Glass) mit Widgets neben den Apps. Besonderheit:
das Widget „Agenten-Sitzungen“ zeigt alle laufenden Claude-Code- und Codex-Sitzungen
dieses Macs. Hintergrund-App (LSUIElement), kein Server, keine Datenbank, keine Fremdpakete.
Vorbild für Bedienung und Verhalten: das macOS-Dock.

## Aufbau

- `Sources/NeoDockKit/` Logik ohne UI, voll getestet:
  - `ClaudeSessionSource` liest `~/.claude/sessions/<pid>.json` (status busy|idle|waiting|shell), Lebendprobe kill(pid,0).
  - `CodexSessionSource` liest `~/.codex/state_5.sqlite` (nur lesend, Tabelle `threads`, letzte 3 h, ohne Archiv/Subagenten),
    Zustand aus dem Schwanz der Rollout-Datei (`CodexRollout`: task_started/task_complete, offene `request_user_input`).
  - `ClaudeDesktopSessionSource` Sitzungen der Claude-Desktop-App (Code-Bereich, Agentenmodus/Cowork) aus
    `~/Library/Application Support/Claude/{claude-code-sessions,local-agent-mode-sessions}/<konto>/<org>/local_*.json`.
    Normale Chats liegen nicht lokal.
  - `Magnification` Dock-Vergrößerung (Kosinus-Glocke + Verschiebung der Nachbarn).
  - `DockArea` belegte Fläche der Leiste, Kürzen von Fenstern davor.
  - `LSAppInfo` zerlegt die Ausgabe von `/usr/bin/lsappinfo`.
  - `FileMemo` Ergebnis je Datei, gültig solange Größe und Änderungszeit gleich sind: Die Quellen laufen alle 2 s, unveränderte Dateien kosten nur ein `stat`.
- `Sources/NeoDock/` die App:
  - `Dock/DockPanel.swift` Panel (rahmenlos, nicht aktivierend, Ebene über dem Systemdock, alle Spaces) + `DockController`.
    Position `DockEdge` (unten/links/rechts): `barLength` läuft entlang der Leiste, `barDepth`/`panelDepth` quer dazu.
    `AppsRowView` rechnet in der Hauptachse m und setzt sie erst in `rect`, `iconPosition`, `dotPosition` um.
  - `Dock/DockRootView.swift` Leiste: Apps | Trenner | Widgets auf einer Glasfläche.
  - `Dock/CardController.swift` aufgeklappte Widget-Karte als eigenes Panel.
  - `Widgets/` Kacheln (Klick = schnelle Aktion, Halten = Karte): `WidgetView` je `WidgetKind`, `Cards.swift`
    je `CardKind`, Seiten-Umschalter in `WidgetTile.swift`. Widgets: Sitzungen, Uhr, Fokus, Kalender, Rechner,
    Zwischenablage, Farbwähler, Passwort, Notiz, Lautstärke, Speicher, Wach halten, Akku.
  - `Dock/StacksRow.swift` minimierte Fenster (aus dem Dock-Durchlauf von `BadgeMonitor`), Ordner-Stapel (Ordner per Ziehen ablegen, Rechtsklick entfernt) + Papierkorb.
  - `Settings/` `DockSettings` (UserDefaults: Widgets/Reihenfolge, Größe, Vergrößerung, angeheftete Apps, Stapel)
    und das Einstellungsfenster. Angeheftete Apps und Stapel werden beim ersten Start aus `com.apple.dock` übernommen (nur gelesen).
  - `System/` Apps (angeheftete aus `com.apple.dock` nur gelesen + laufende), Prozessbaum (sysctl/libproc),
    `AttentionMonitor` (Icons hüpfen bei `requestUserAttention`: `lsappinfo listen` als Wecker, Stand aus `LSWantsAttention`),
    `SessionJumper` (holt die beherbergende App per LaunchServices nach vorne), `SessionStore` (Takt 2 s, I/O abseits des Main-Threads).

## Bauen und prüfen

- Tests: `swift test --scratch-path ~/Library/Developer/NeoDock/test-build`
- Bauen + installieren: `./build.sh` (`--open` startet neu). Warnungen beheben.
- Schnelle Prüfbuilds nie in den Scratch-Ordner von build.sh: `swift build --scratch-path ~/Library/Developer/NeoDock/check-build`
  (gemischte Debug/Release-Builds im selben Ordner ließen den Release-Stand veralten).
- Sichtprüfung ohne Bildschirmaufnahme-Recht: `NEODOCK_SNAPSHOT=<ordner> ~/Applications/NeoDock.app/Contents/MacOS/NeoDock`
  schreibt `dock.png` und `card-<name>.png`; `NEODOCK_SNAPSHOT_CARDS=focus,folder,…` wählt die Karten.
  Karten mit Texteingabe (calculator, note) werden Key-Window und fangen Tastendrücke ab — nur öffnen,
  wenn niemand am Rechner tippt. Grenze: Liquid Glass und vibrante Flächen zeichnet erst der
  Window-Server — sie fehlen im Snapshot; Glas nur am echten Bildschirm beurteilen.
- Geometrie: Fenstergrenzen über `CGWindowListCopyWindowInfo` (geht ohne Bildschirmaufnahme-Recht).
  Vorher `lsappinfo front` prüfen: Steht `loginwindow` vorn, ist der Mac gesperrt, alle Rahmen sind um 0,9 skaliert und Animationen stehen.
- Position prüfen ohne Einstellung zu schreiben: Binary mit `-dockEdge left` starten. Bei Leiste links zeigt der Snapshot
  die App-Reihe zusätzlich doppelt groß: Das ist ein Fehler von `Snapshot.write`, nicht vom Fenster.
- Automatisch geprüft wird nur die Logik; ein Umbau an der Leiste unten gehört per Pixelvergleich alter/neuer Snapshot belegt.

## Regeln

- Nutzer-Einstellungen anderer Apps nur lesen. Ausnahme: `SystemDockHider`, ausdrücklich einzuschalten, mit absturzsicherer
  Wiederherstellung durch den Wächter (`SystemDockGuard`).
- `DockReservation` meldet die Leistenfläche über die private Funktion `SLSSetDockRectWithReason` als Dock-Fläche, damit
  `visibleFrame` stimmt. Nur unten und nur solange der Wächter läuft: Die Fläche überlebt das Ende von NeoDock und einen
  Dock-Neustart, der Wächter gibt sie mit `NeoDock --release-dock-area` frei. Das Dock überschreibt sie bei App-Starts,
  deshalb der 1-s-Takt. An der Seite geht es nicht: AppKit zieht immer unten ab, in allen Varianten gemessen.
- Die Fläche wirkt nur auf neu gestartete Apps: Laufende speichern `visibleFrame` zwischen, das Signal zum Neulesen sendet allein
  das macOS-Dock. Darum `WindowGuard` (AXObserver je App): Wächst ein Fenster in die Leiste, wird es gekürzt. Ein Zoom-Test
  taugt nur mit einer App, die schon vor der Reservierung lief.
  Der Druck auf `AXZoomButton` löst Vollbild aus, nicht Zoom. Zoomen per `set zoomed of window 1 to true` (Mail) oder `NSWindow.zoom`.
  `pgrep -f …/NeoDock` trifft auch das Wächter-Skript, also `pgrep -x NeoDock`.
- Datenquellen von Claude/Codex nur lesend öffnen; nichts in `~/.claude` oder `~/.codex` schreiben.
- Abstände aus `Space`/`DockMetrics` (`UI/Tokens.swift`), 4-pt-Raster: `tools/grid-lint.sh`.
- Liquid Glass nur für schwebende Flächen (Leiste, Karte, Namensschild), nicht für Inhalte.

## Git

Nach jeder funktionierenden Änderung committen; die Nachricht sagt, was man jetzt kann.

## Veröffentlichung (GitHub)

- Öffentliches Repo: `github.com/neothinkgmbh/NeoDock` (Zweig `main`). Es wird NUR aus dem lokalen Zweig `public`
  gespeist; die Entwicklungshistorie (`feat/…`, mit privater Mail) wird nie gepusht.
- Update: auf `public` die geänderten Dateien vom Arbeitszweig übernehmen, dann committen mit
  `GIT_AUTHOR_NAME="neothink GmbH" GIT_AUTHOR_EMAIL="290958107+neothinkgmbh@users.noreply.github.com"` (dasselbe für
  `GIT_COMMITTER_*`) und `git push https://github.com/neothinkgmbh/NeoDock.git public:main`.
- Vor jedem Push prüfen: keine Mail, keine Home-Pfade, keine internen Notizen (`git grep` auf `public`).
