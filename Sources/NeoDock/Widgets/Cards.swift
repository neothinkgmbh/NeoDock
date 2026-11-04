import AppKit
import NeoDockKit
import SwiftUI

/// Inhalt der aufgeklappten Karte je Widget.
struct CardContent: View {
    let kind: CardKind
    @Bindable var model: DockModel
    let close: () -> Void

    var body: some View {
        Group {
            switch kind {
            case .sessions:
                SessionsCard(store: model.sessions) { session in close(); SessionJumper.jump(to: session) }
            case .focus: FocusCard(focus: model.focus)
            case .calendar: CalendarCard(calendar: model.calendar)
            case .calculator: CalculatorCard()
            case .clipboard: ClipboardCard(history: model.clipboard.history.items, close: close)
            case .colors: ColorsCard(colors: model.colors, close: close)
            case .password: PasswordCard(settings: model.settings, close: close)
            case .note: NoteCard(notes: model.notes)
            case .volume: VolumeCard(volume: model.volume)
            case .folder(let url): FolderCard(folder: url, close: close)
            }
        }
        .onExitCommand(perform: close)
    }
}

private struct CardHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct FocusCard: View {
    let focus: FocusService

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            CardHeader(title: "Fokus-Timer")
            Text(FocusTimer.label(focus.remaining))
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
            HStack {
                ForEach(FocusService.presets, id: \.self) { seconds in
                    Button("\(Int(seconds / 60)) min") { focus.setDuration(seconds) }
                        .buttonStyle(.bordered)
                        .tint(focus.timer.duration == seconds ? .accentColor : nil)
                }
            }
            HStack {
                Button(focus.timer.isRunning ? "Pause" : "Start", action: focus.toggle)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Zurücksetzen", action: focus.reset).buttonStyle(.bordered)
            }
        }
        .padding(Space.lg)
    }
}

struct CalendarCard: View {
    let calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            CardHeader(title: "Als Nächstes")
            if calendar.events.isEmpty {
                ContentUnavailableView("Keine Termine", systemImage: "calendar",
                                       description: Text("In den nächsten \(Int(calendar.lookahead / 3600)) Stunden ist nichts eingetragen."))
            } else {
                ForEach(calendar.events) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.isAllDay ? "ganztags" : event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                        Text(event.title).lineLimit(1)
                    }
                }
            }
            Button("Kalender öffnen", action: CalendarService.openCalendar).buttonStyle(.bordered)
        }
        .padding(Space.lg)
    }
}

struct CalculatorCard: View {
    @State private var expression = ""
    @State private var copied = false
    @FocusState private var focused: Bool

    private var result: String? {
        guard let value = try? Calculator.evaluate(expression) else { return nil }
        return Calculator.format(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            CardHeader(title: "Rechner", detail: copied ? "Ergebnis kopiert ✓" : "⏎ kopiert das Ergebnis")
            TextField("z. B. 1200 * 19 %", text: $expression)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())
                .focused($focused)
                .onSubmit(copyResult)
                .onChange(of: expression) { copied = false }
            Text(result.map { "= \($0)" } ?? " ")
                .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                .textSelection(.enabled)
        }
        .padding(Space.lg)
        .focusWhenKey($focused)
    }

    private func copyResult() {
        guard let result else { return }
        ClipboardService.copy(result)
        copied = true
    }
}

struct ClipboardCard: View {
    static let displayLength = 500
    let history: [String]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            CardHeader(title: "Zwischenablage", detail: "nur Text, nur bis zum Beenden")
            if history.isEmpty {
                ContentUnavailableView("Noch nichts kopiert", systemImage: "doc.on.clipboard")
            } else {
                ScrollView {
                    VStack(spacing: Space.xxs) {
                        ForEach(history, id: \.self) { item in
                            CardRow(action: { ClipboardService.copy(item); close() }) {
                                Text(item.prefix(ClipboardCard.displayLength)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(Space.lg)
    }
}

struct ColorsCard: View {
    let colors: ColorService
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            CardHeader(title: "Farbwähler", detail: "Klick kopiert den Hex-Wert")
            HStack(spacing: Space.sm) {
                ForEach(colors.recent, id: \.self) { hex in
                    Button { ClipboardService.copy(hex); close() } label: {
                        VStack(spacing: Space.xs) {
                            RoundedRectangle(cornerRadius: Space.sm).fill(Color(hex: hex) ?? .clear)
                                .frame(width: 40, height: 40)
                            Text(hex).font(.caption2.monospaced())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Farbe vom Bildschirm wählen") { close(); colors.pick() }.buttonStyle(.borderedProminent)
        }
        .padding(Space.lg)
    }
}

struct PasswordCard: View {
    @Bindable var settings: DockSettings
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            CardHeader(title: "Passwort", detail: "landet vertraulich markiert in der Zwischenablage")
            Stepper("Länge: \(settings.passwordLength) Zeichen", value: $settings.passwordLength,
                    in: DockSettings.passwordRange)
            Button("Neues Passwort kopieren") {
                ClipboardService.copy(PasswordGenerator.generate(length: settings.passwordLength), concealed: true)
                close()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Space.lg)
    }
}

struct NoteCard: View {
    @Bindable var notes: NoteStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            CardHeader(title: "Notiz", detail: "wird automatisch gesichert")
            TextEditor(text: $notes.text)
                .font(.body)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(Space.xs)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Space.sm))
                .frame(height: 220)
        }
        .padding(Space.lg)
        .focusWhenKey($focused)
    }
}

struct VolumeCard: View {
    let volume: VolumeService

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            CardHeader(title: "Lautstärke", detail: volume.isMuted ? "stumm" : "\(Int((volume.volume * 100).rounded())) %")
            HStack {
                Button { volume.toggleMute() } label: {
                    Image(systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                Slider(value: Binding(get: { Double(volume.volume) }, set: { volume.setVolume(Float($0)) }), in: 0...1)
            }
        }
        .padding(Space.lg)
    }
}

struct FolderCard: View {
    let folder: URL
    let close: () -> Void
    @State private var items: [FolderListing.Item]?
    @State private var isLoaded = false
    @Environment(\.cardController) private var cardController

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            CardHeader(title: FileManager.default.displayName(atPath: folder.path), detail: "Klick öffnet · ziehen legt ab")
            if !isLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if let items, !items.isEmpty {
                let asGrid = FolderListing.holdsApps(items.map(\.url))
                let rows = asGrid ? (items.count + DockMetrics.folderGridColumns - 1) / DockMetrics.folderGridColumns : items.count
                let contentHeight = CGFloat(rows) * (asGrid ? DockMetrics.folderCellHeight : DockMetrics.folderRowHeight)
                ScrollView {
                    if asGrid { grid(items) } else { list(items) }
                }
                .frame(height: min(contentHeight, DockMetrics.folderContentMaxHeight))
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ContentUnavailableView(items == nil ? "Kein Zugriff" : "Leer", systemImage: "folder",
                                       description: Text(items == nil ? "macOS hat den Zugriff auf diesen Ordner nicht erlaubt." : ""))
            }
            Button("Im Finder öffnen") { NSWorkspace.shared.open(folder); close() }.buttonStyle(.bordered)
        }
        .padding(Space.lg)
        .task(id: folder) {
            // Abseits des Main-Threads: große Ordner und die erste Datenschutz-Abfrage blockieren nicht.
            let folder = folder
            items = await Task.detached(priority: .userInitiated) { FolderListing.recent(in: folder) }.value
            isLoaded = true
        }
        // Beim Öffnen stand hier nur der Ladekreis, die Karte war entsprechend niedrig.
        .onChange(of: isLoaded) { DispatchQueue.main.async { cardController?.refit() } }
    }

    private func list(_ items: [FolderListing.Item]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                CardRow(action: { open(item) }) {
                    HStack(spacing: Space.sm) {
                        icon(item, size: 24)
                        Text(FolderListing.displayName(item.url)).lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text(item.modified.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(height: DockMetrics.folderRowHeight)
                .draggableFile(item, preview: icon(item, size: DockMetrics.folderGridIcon))
            }
        }
    }

    private func grid(_ items: [FolderListing.Item]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: DockMetrics.folderGridColumns)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(items) { item in
                CardRow(action: { open(item) }) {
                    VStack(spacing: Space.xs) {
                        icon(item, size: DockMetrics.folderGridIcon)
                        Text(FolderListing.displayName(item.url))
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: DockMetrics.folderCellHeight)
                .help(FolderListing.displayName(item.url))
                .draggableFile(item, preview: icon(item, size: DockMetrics.folderGridIcon))
            }
        }
    }

    private func icon(_ item: FolderListing.Item, size: CGFloat) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: size, height: size)
    }

    private func open(_ item: FolderListing.Item) {
        NSWorkspace.shared.open(item.url)
        close()
    }
}

private extension View {
    /// Aus dem Stapel herausziehen — in Finder, Mail, auf den Schreibtisch …
    func draggableFile(_ item: FolderListing.Item, preview: some View) -> some View {
        onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() } preview: { preview }
    }
}

/// Zeile mit Hover-Hervorhebung, wie in der Sitzungsliste.
struct CardRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: Space.sm))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension View {
    /// Fokus ins Feld, sobald die Karte Key-Window ist — ein in onAppear gesetzter Fokus kommt
    /// nicht an, weil das Panel zu dem Zeitpunkt noch nicht key ist (gemessen).
    func focusWhenKey(_ focused: FocusState<Bool>.Binding) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focused.wrappedValue = true
        }
        .onAppear { focused.wrappedValue = true }
    }
}
