import AppKit
import NeoDockKit
import SwiftUI

/// Eine Kachel je Widget-Art.
struct WidgetView: View {
    let kind: WidgetKind
    @Bindable var model: DockModel
    @State private var flash: String?

    private func open(_ card: CardKind) -> (CGFloat) -> Void { { model.onOpenCard?(card, $0) } }
    private func toggle(_ card: CardKind) -> (CGFloat) -> Void { { model.onToggleCard?(card, $0) } }

    var body: some View {
        switch kind {
        case .sessions:
            SessionsWidget(store: model.sessions, hold: open(.sessions), toggle: toggle(.sessions))
        case .clock:
            ClockWidget()
        case .battery:
            if let battery = model.battery { BatteryWidget(status: battery) }
        case .focus:
            let focus = model.focus
            WidgetTile(caption: focus.justFinished ? "fertig ✓" : focus.timer.isRunning ? "Fokus läuft" : "Fokus",
                       tap: focus.toggle, hold: open(.focus),
                       face: AnyView(RingFace(progress: focus.remaining / max(1, focus.timer.duration), tint: .accentColor,
                                              symbol: focus.timer.isRunning ? "pause.fill" : "play.fill",
                                              label: "\(Int((focus.remaining / 60).rounded(.up)))")),
                       tint: .accentColor, isActive: focus.timer.isRunning) {
                Text(FocusTimer.label(focus.remaining))
                    .foregroundStyle(focus.timer.isRunning ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
        case .calendar:
            calendarTile
        case .calculator:
            WidgetTile(caption: "rechnen", hold: open(.calculator), tapAt: toggle(.calculator),
                       face: AnyView(GlyphFace(symbol: "plus.forwardslash.minus", tint: .orange)), tint: .orange) {
                Text("Rechner")
            }
        case .clipboard:
            WidgetTile(caption: model.clipboard.history.items.first.map(Self.preview) ?? "noch leer",
                       hold: open(.clipboard), tapAt: toggle(.clipboard),
                       face: AnyView(GlyphFace(symbol: "doc.on.clipboard.fill", tint: .teal)), tint: .teal) {
                Text("Ablage")
            }
        case .colorPicker:
            let last = model.colors.recent.first.flatMap(Color.init(hex:))
            WidgetTile(caption: model.colors.recent.first ?? "Farbe wählen", tap: model.colors.pick, hold: open(.colors),
                       face: AnyView(SwatchFace(color: last)), tint: last ?? .pink) {
                Text("Farbe")
            }
        case .password:
            WidgetTile(caption: flash ?? "\(model.settings.passwordLength) Zeichen", tap: copyPassword,
                       hold: open(.password),
                       face: AnyView(GlyphFace(symbol: "key.fill", tint: .indigo)), tint: .indigo, isActive: flash != nil) {
                Text("Passwort")
            }
        case .note:
            WidgetTile(caption: "notieren", hold: open(.note), tapAt: toggle(.note),
                       face: AnyView(GlyphFace(symbol: "note.text", tint: .yellow)), tint: .yellow) {
                Text(Self.preview(model.notes.text).isEmpty ? "Notiz" : Self.preview(model.notes.text))
            }
        case .volume:
            let volume = model.volume
            WidgetTile(caption: "Lautsprecher", tap: volume.toggleMute, hold: open(.volume),
                       face: AnyView(RingFace(progress: volume.isMuted ? 0 : Double(volume.volume), tint: .blue,
                                              symbol: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                              label: volume.isMuted ? nil : "\(Int((volume.volume * 100).rounded()))")),
                       tint: .blue) {
                Text(volume.isMuted ? "stumm" : "\(Int((volume.volume * 100).rounded())) %")
            }
        case .storage:
            if let storage = model.storage {
                let used = storage.total > 0 ? 1 - Double(storage.available) / Double(storage.total) : 0
                WidgetTile(caption: "frei", tap: StorageReader.openSettings,
                           face: AnyView(RingFace(progress: used, tint: used > 0.9 ? .red : .purple, symbol: "internaldrive.fill")),
                           tint: .purple) {
                    Text(storage.available.formatted(.byteCount(style: .file)))
                }
            }
        case .keepAwake:
            WidgetTile(caption: "Wach halten", tap: model.keepAwake.toggle,
                       face: AnyView(GlyphFace(symbol: "cup.and.saucer.fill", tint: model.keepAwake.isOn ? .orange : .gray,
                                               glowing: model.keepAwake.isOn)),
                       tint: .orange, isActive: model.keepAwake.isOn) {
                Text(model.keepAwake.isOn ? "An" : "Aus")
                    .foregroundStyle(model.keepAwake.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
        }
    }

    @ViewBuilder private var calendarTile: some View {
        let calendar = model.calendar
        if !calendar.hasAccess {
            WidgetTile(caption: "Zugriff erlauben", tap: { Task { await calendar.requestAccess() } },
                       face: AnyView(CalendarFace(date: Date())), tint: .red) {
                Text("Kalender")
            }
        } else if let next = calendar.next {
            WidgetTile(caption: next.title, tap: CalendarService.openCalendar, hold: open(.calendar),
                       face: AnyView(CalendarFace(date: next.start)), tint: .red) {
                Text(next.isAllDay ? "ganztags" : next.start.formatted(date: .omitted, time: .shortened))
            }
        } else {
            WidgetTile(caption: "keine Termine", tap: CalendarService.openCalendar, hold: open(.calendar),
                       face: AnyView(CalendarFace(date: Date())), tint: .red) {
                Text("Frei")
            }
        }
    }

    private func copyPassword() {
        ClipboardService.copy(PasswordGenerator.generate(length: model.settings.passwordLength), concealed: true)
        flash = "kopiert ✓"
        Task {
            try? await Task.sleep(for: DockMetrics.flashDuration)
            flash = nil
        }
    }

    static let previewLength = 120

    /// Erste Zeile, gekürzt — ohne den ganzen Text zu zerlegen (Kopien können Megabytes groß sein).
    static func preview(_ text: String) -> String {
        String(text.prefix(while: { !$0.isNewline }).prefix(previewLength)).trimmingCharacters(in: .whitespaces)
    }
}

extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
