import AppKit
import NeoDockKit
import Observation

/// Fokus-Timer mit Sekundentakt nur, solange er läuft; Ton bei Ablauf.
@Observable
final class FocusService {
    private(set) var timer: FocusTimer
    private(set) var now = Date()
    private(set) var justFinished = false
    @ObservationIgnored private var ticker: Task<Void, Never>?
    static let presets: [TimeInterval] = [5 * 60, 15 * 60, 25 * 60, 50 * 60]
    static let finishSound = "Glass"

    init(minutes: Int) { timer = FocusTimer(duration: TimeInterval(minutes * 60)) }

    var remaining: TimeInterval { timer.remaining(at: now) }

    func toggle() {
        justFinished = false
        if timer.isRunning { timer.pause(at: Date()) } else { timer.start(at: Date()); tick() }
        now = Date()
    }

    func reset() {
        timer.reset()
        justFinished = false
        now = Date()
    }

    func setDuration(_ seconds: TimeInterval) {
        timer.setDuration(seconds)
        justFinished = false
        now = Date()
    }

    private func tick() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while let self, self.timer.isRunning, !Task.isCancelled {
                self.now = Date()
                if self.timer.isFinished(at: self.now) {
                    self.timer.reset()
                    self.justFinished = true
                    NSSound(named: Self.finishSound)?.play()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
