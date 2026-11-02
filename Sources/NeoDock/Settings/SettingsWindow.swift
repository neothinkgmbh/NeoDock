import AppKit
import SwiftUI

enum SettingsTab: Hashable { case general, widgets, sessions }

/// Eigenes Einstellungsfenster: die Settings-Szene von SwiftUI lässt sich aus einer
/// Hintergrund-App ohne SettingsLink nicht zuverlässig öffnen.
final class SettingsWindowController {
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(settings: DockSettings, model: DockModel, tab: SettingsTab) {
        selection.tab = tab
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, model: model, selection: selection))
            // Nicht aktivierendes Panel: wird Key-Window und bekommt die Tastatur, ohne dass macOS die
            // Hintergrund-App aktivieren muss — das verweigert es ohne Nutzerklick (gemessen).
            let window = KeyablePanel(contentViewController: host)
            window.title = "NeoDock-Einstellungen"
            window.styleMask = [.titled, .closable, .nonactivatingPanel]
            window.isFloatingPanel = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    var isVisible: Bool { window?.isVisible ?? false }
    var contentView: NSView? { window?.contentView }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}

struct SettingsView: View {
    @Bindable var settings: DockSettings
    let model: DockModel
    @Bindable var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettings(settings: settings, model: model)
                .tabItem { Label("Allgemein", systemImage: "dock.rectangle") }.tag(SettingsTab.general)
            WidgetSettings(settings: settings, model: model)
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }.tag(SettingsTab.widgets)
            SessionSettings(settings: settings)
                .tabItem { Label("Sitzungen", systemImage: "sparkles") }.tag(SettingsTab.sessions)
        }
        .frame(width: 480, height: 560)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: DockSettings
    let model: DockModel
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Größe") {
                Slider(value: $settings.maxIconSize, in: DockSettings.iconRange, step: 4) {
                    Text("Icongröße")
                } minimumValueLabel: { Image(systemName: "app").imageScale(.small) }
                  maximumValueLabel: { Image(systemName: "app").imageScale(.large) }
            }
            Section("Aussehen") {
                Picker("Glas", selection: $settings.glassStyle) {
                    ForEach(GlassStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Vergrößerung") {
                Toggle("Icons unter dem Zeiger vergrößern", isOn: $settings.magnification)
                Slider(value: $settings.magnificationScale, in: DockSettings.scaleRange) { Text("Stärke") }
                    .disabled(!settings.magnification)
            }
            Section {
                Toggle("Leiste automatisch ein- und ausblenden", isOn: $settings.autohide)
                Toggle("macOS-Dock ausblenden, solange NeoDock läuft", isOn: $settings.hideSystemDock)
            } header: {
                Text("Ein- und Ausblenden")
            } footer: {
                Text("Beim Beenden — auch nach einem Absturz — stellt NeoDock die Dock-Einstellungen von macOS wieder her.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Kennzahlen am Icon") {
                BadgePermissionRow(badges: model.badges)
            }
            Section("Start") {
                Toggle("Beim Anmelden starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in settings.launchAtLogin = on }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }
}

/// Welche Widgets in der Leiste stehen, in welcher Reihenfolge, und ihre Optionen.
private struct WidgetSettings: View {
    @Bindable var settings: DockSettings
    let model: DockModel

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(settings.orderedWidgets) { kind in
                        Toggle(isOn: Binding(get: { settings.isEnabled(kind) }, set: { settings.setEnabled(kind, $0) })) {
                            Label(kind.title, systemImage: kind.symbol)
                                .foregroundStyle(settings.isEnabled(kind) ? .primary : .secondary)
                        }
                        .moveDisabled(!settings.isEnabled(kind))
                    }
                    .onMove(perform: move)
                }
                .frame(minHeight: 300)
            } header: {
                Text("Widgets in der Leiste")
            } footer: {
                Text("Eingeschaltete Widgets per Ziehen sortieren. Rechtsklick auf ein Widget in der Leiste entfernt es.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Darstellung", selection: $settings.widgetStyle) {
                    ForEach(WidgetStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Breite (mit Text)", selection: $settings.widgetWidth) {
                    ForEach(WidgetWidth.allCases) { Text($0.title).tag($0) }
                }
                .disabled(settings.widgetStyle == .iconOnly)
                Stepper("Widgets je Seite: \(settings.widgetsPerPage)", value: $settings.widgetsPerPage,
                        in: DockSettings.perPageRange)
                Button("Standard wiederherstellen", action: settings.resetWidgets)
            }
            Section("Optionen") {
                Picker("Fokus-Timer, Standarddauer", selection: $settings.focusMinutes) {
                    ForEach(DockSettings.focusChoices, id: \.self) { Text("\($0) min").tag($0) }
                }
                .onChange(of: settings.focusMinutes) { _, minutes in
                    if !model.focus.timer.isRunning { model.focus.setDuration(TimeInterval(minutes * 60)) }
                }
                Picker("Kalender, Vorschau", selection: $settings.calendarHours) {
                    ForEach(DockSettings.calendarChoices, id: \.self) { Text("\($0) Stunden").tag($0) }
                }
                .onChange(of: settings.calendarHours) { _, hours in
                    model.calendar.lookahead = TimeInterval(hours * 3600)
                    model.calendar.reload()
                }
                Stepper("Passwortlänge: \(settings.passwordLength) Zeichen", value: $settings.passwordLength,
                        in: DockSettings.passwordRange)
            }
        }
        .formStyle(.grouped)
    }

    /// Verschieben nur innerhalb der eingeschalteten Widgets (sie stehen oben in der Liste).
    private func move(from source: IndexSet, to destination: Int) {
        let enabledCount = settings.enabledWidgets.count
        guard source.allSatisfy({ $0 < enabledCount }) else { return }
        settings.enabledWidgets.move(fromOffsets: source, toOffset: min(destination, enabledCount))
    }
}

private struct SessionSettings: View {
    @Bindable var settings: DockSettings

    var body: some View {
        Form {
            Section("Quellen") {
                Toggle("Claude Code", isOn: $settings.showClaude)
                Toggle("Codex", isOn: $settings.showCodex)
            }
            Section("Codex") {
                Stepper("Threads der letzten \(Int(settings.codexHours)) h", value: $settings.codexHours,
                        in: DockSettings.codexHoursRange, step: 1)
                    .disabled(!settings.showCodex)
            }
        }
        .formStyle(.grouped)
    }
}

/// Ob NeoDock die Kennzahlen lesen darf (Bedienungshilfen), mit Weg zur Systemeinstellung.
private struct BadgePermissionRow: View {
    let badges: BadgeMonitor

    var body: some View {
        if badges.isTrusted {
            Label("Freigegeben — ungelesene Mails & Co. erscheinen als rote Zahl", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            HStack {
                Label("Braucht die Bedienungshilfen-Freigabe", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Freigabe öffnen") { NSWorkspace.shared.open(BadgeMonitor.settingsURL) }
            }
        }
    }
}
