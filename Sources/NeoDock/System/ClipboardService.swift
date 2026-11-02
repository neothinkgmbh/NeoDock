import AppKit
import NeoDockKit
import Observation

/// Verlauf der Zwischenablage — nur Text, nur im Speicher. Einträge, die Passwortmanager als
/// vertraulich oder flüchtig markieren (nspasteboard.org), werden nicht aufgenommen.
@Observable
final class ClipboardService {
    private(set) var history = ClipboardHistory(limit: 12)
    @ObservationIgnored private var lastChange = NSPasteboard.general.changeCount
    @ObservationIgnored private var task: Task<Void, Never>?
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let pollInterval: Duration = .seconds(1)
    /// Größere Texte (Logs, Dumps) kommen nicht in den Verlauf.
    static let maxLength = 1_000_000

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        let types = board.types ?? []
        guard !types.contains(Self.concealed), !types.contains(Self.transient),
              let text = board.string(forType: .string), text.utf8.count <= Self.maxLength else { return }
        history.add(text)
    }

    /// Text in die Zwischenablage; vertraulich markiert, wenn es ein Geheimnis ist.
    static func copy(_ text: String, concealed: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes(concealed ? [.string, Self.concealed] : [.string], owner: nil)
        board.setString(text, forType: .string)
        // Markierung mit (leeren) Daten: manche Verlaufsprogramme prüfen Daten statt Typen.
        if concealed { board.setData(Data(), forType: Self.concealed) }
    }
}

/// Farbe vom Bildschirm aufnehmen und als Hex kopieren.
@Observable
final class ColorService {
    private(set) var recent: [String] = []
    static let limit = 6

    func pick() {
        Task {
            guard let color = await NSColorSampler().sample(), let hex = Self.hex(color) else { return }
            ClipboardService.copy(hex)
            recent.removeAll { $0 == hex }
            recent.insert(hex, at: 0)
            if recent.count > Self.limit { recent.removeLast() }
        }
    }

    nonisolated static func hex(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((srgb.redComponent * 255).rounded()), g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Eine Notiz, gesichert in Application Support/NeoDock/notiz.txt.
@Observable
final class NoteStore {
    var text: String { didSet { scheduleSave() } }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    static let url: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "NeoDock", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "notiz.txt")
    }()
    static let saveDelay: Duration = .milliseconds(500)

    init() { text = (try? String(contentsOf: Self.url, encoding: .utf8)) ?? "" }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            do { try snapshot.write(to: Self.url, atomically: true, encoding: .utf8) } catch {
                NSLog("NeoDock: Notiz konnte nicht gesichert werden: \(error.localizedDescription)")
            }
        }
    }
}
