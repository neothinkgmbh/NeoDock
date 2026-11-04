import Foundation

/// Liest das Ende eines Claude-Code-Transkripts (`~/.claude/projects/<projekt>/<sessionId>.jsonl`).
/// Die Registry meldet nach einer Rückfrage nur `idle` — ob der letzte Zug mit einer Frage an den
/// Menschen endete, steht nur im Transkript (dieselbe Regel nutzt der Leitstand).
public enum ClaudeTranscript {
    static let tailBytes = 262_144
    static let questionWindow = 240

    private struct Line: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: Content?
        }
        enum Content: Decodable {
            case text(String), parts([Part])
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .text(s) } else { self = .parts(try c.decode([Part].self)) }
            }
        }
        struct Part: Decodable {
            let type: String?
            let text: String?
        }
        let type: String?
        let message: Message?
    }

    /// Endet der letzte abgeschlossene Zug mit einer Frage des Assistenten?
    public static func endsWithQuestion<S: Sequence>(lines: S) -> Bool where S.Element: StringProtocol {
        let decoder = JSONDecoder()
        var lastText: String?   // letzter Assistenten-Text, solange danach nichts anderes kam
        for raw in lines {
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)),
                  let content = line.message?.content else { continue }
            switch (line.type, content) {
            case ("assistant", .parts(let parts)):
                if parts.contains(where: { $0.type == "tool_use" }) {
                    lastText = nil                       // arbeitet weiter
                } else if let text = parts.last(where: { $0.type == "text" })?.text {
                    lastText = text
                }
            case ("user", _):
                lastText = nil                           // Mensch hat geantwortet oder Werkzeug-Ergebnis
            default:
                break
            }
        }
        guard let text = lastText else { return false }
        var ending = text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(questionWindow)
        while let last = ending.last, "`*_)]".contains(last) || last.isWhitespace { ending = ending.dropLast() }
        return ending.hasSuffix("?")
    }

    public static func url(for sessionId: String, projectsRoot: URL) -> URL? {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
        return dirs.lazy.map { $0.appending(path: "\(sessionId).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static let questions = FileMemo<Bool>()

    public static func endsWithQuestion(url: URL) -> Bool {
        questions.value(for: url) { readEndsWithQuestion(url: url) }
    }

    private static func readEndsWithQuestion(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        return endsWithQuestion(lines: text.split(separator: "\n"))
    }
}
