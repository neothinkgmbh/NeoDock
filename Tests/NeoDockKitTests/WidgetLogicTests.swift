import Foundation
import Testing
@testable import NeoDockKit

@Suite struct CalculatorTests {
    @Test("Grundrechenarten mit Punkt vor Strich", arguments: [
        ("1 + 2 * 3", 7.0), ("(1 + 2) * 3", 9.0), ("10 / 4", 2.5), ("2 ^ 10", 1024.0),
        ("-3 + 5", 2.0), ("2 * -3", -6.0), ("1,5 + 1,5", 3.0), ("200 * 15 %", 30.0), ("2^3^2", 512.0),
    ])
    func evaluates(expression: String, expected: Double) throws {
        #expect(try Calculator.evaluate(expression) == expected)
    }

    @Test("ungültige Eingaben werfen statt abzustürzen", arguments: ["", "1 +", "(1", "1 / 0", "abc", "1 2", ")"])
    func rejects(expression: String) {
        #expect(throws: Calculator.Failure.self) { try Calculator.evaluate(expression) }
    }

    @Test("Ergebnis wird lesbar formatiert")
    func format() {
        #expect(Calculator.format(2.5) == "2,5")
        #expect(Calculator.format(1024) == "1024")
        #expect(Calculator.format(1.0 / 3.0) == "0,3333333333")
    }
}

@Suite struct PasswordGeneratorTests {
    @Test("Länge und alle Zeichenklassen")
    func classes() {
        for _ in 0..<50 {
            let pw = PasswordGenerator.generate(length: 20)
            #expect(pw.count == 20)
            #expect(pw.contains { $0.isLowercase })
            #expect(pw.contains { $0.isUppercase })
            #expect(pw.contains { $0.isNumber })
            #expect(pw.contains { PasswordGenerator.symbols.contains($0) })
            #expect(!pw.contains { "0O1lI".contains($0) })
        }
    }

    @Test("Mindestlänge wird erzwungen und Ergebnisse unterscheiden sich")
    func minimumAndUnique() {
        #expect(PasswordGenerator.generate(length: 2).count == PasswordGenerator.minimumLength)
        #expect(Set((0..<20).map { _ in PasswordGenerator.generate(length: 16) }).count == 20)
    }
}

@Suite struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("läuft, pausiert, setzt fort, endet")
    func lifecycle() {
        var timer = FocusTimer(duration: 60)
        #expect(timer.remaining(at: t0) == 60)
        timer.start(at: t0)
        #expect(timer.remaining(at: t0 + 20) == 40)
        timer.pause(at: t0 + 20)
        #expect(timer.remaining(at: t0 + 100) == 40)
        #expect(timer.isRunning == false)
        timer.start(at: t0 + 100)
        #expect(timer.remaining(at: t0 + 130) == 10)
        #expect(timer.isFinished(at: t0 + 140))
        #expect(timer.remaining(at: t0 + 500) == 0)
        timer.reset()
        #expect(timer.remaining(at: t0 + 500) == 60)
    }

    @Test("Dauer ändern setzt zurück")
    func changeDuration() {
        var timer = FocusTimer(duration: 60)
        timer.start(at: t0)
        timer.setDuration(300)
        #expect(timer.isRunning == false)
        #expect(timer.remaining(at: t0 + 10) == 300)
    }

    @Test("Anzeige mm:ss")
    func label() {
        #expect(FocusTimer.label(1500) == "25:00")
        #expect(FocusTimer.label(59.2) == "01:00")
        #expect(FocusTimer.label(0) == "00:00")
    }
}

@Suite struct ClipboardHistoryTests {
    @Test("neuester zuerst, ohne Doppel, begrenzt, ohne Leeres")
    func history() {
        var h = ClipboardHistory(limit: 3)
        h.add("a"); h.add("b"); h.add("  "); h.add("a"); h.add("c"); h.add("d")
        #expect(h.items == ["d", "c", "a"])
    }
}
