import Foundation

/// Fokus-Timer als Wert: Laufzeit wird aus Zeitstempeln berechnet, nicht hochgezählt —
/// so stimmt er auch nach Ruhezustand oder einem verpassten Takt.
public struct FocusTimer: Sendable, Equatable {
    public private(set) var duration: TimeInterval
    private var endsAt: Date?
    private var pausedRemaining: TimeInterval?

    public init(duration: TimeInterval) { self.duration = duration }

    public var isRunning: Bool { endsAt != nil }

    public func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }

    public func isFinished(at now: Date) -> Bool { isRunning && remaining(at: now) == 0 }

    public mutating func start(at now: Date) {
        guard !isRunning else { return }
        endsAt = now.addingTimeInterval(pausedRemaining ?? duration)
        pausedRemaining = nil
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    public mutating func reset() {
        endsAt = nil
        pausedRemaining = nil
    }

    public mutating func setDuration(_ seconds: TimeInterval) {
        duration = seconds
        reset()
    }

    public static func label(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Verlauf der Zwischenablage: neuester zuerst, ohne Doppel, begrenzt.
public struct ClipboardHistory: Sendable, Equatable {
    public private(set) var items: [String] = []
    public let limit: Int

    public init(limit: Int) { self.limit = limit }

    public mutating func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }
}
