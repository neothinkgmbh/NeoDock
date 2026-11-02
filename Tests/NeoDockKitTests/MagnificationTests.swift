import Testing
@testable import NeoDockKit

@Suite struct MagnificationTests {
    let centers: [Double] = [26, 86, 146, 206, 266]

    @Test("ohne Zeiger bleibt alles bei 1")
    func noPointer() {
        #expect(Magnification.scales(pointerX: nil, centers: centers, maxScale: 1.6, reach: 150) == [1, 1, 1, 1, 1])
    }

    @Test("Zeiger über einem Icon: dort am größten, Nachbarn symmetrisch kleiner")
    func bell() {
        // Reichweite 100: Icon 1/3 (60 entfernt) wachsen mit, Icon 0/4 (120 entfernt) nicht.
        let s = Magnification.scales(pointerX: 146, centers: centers, maxScale: 1.6, reach: 100)
        #expect(abs(s[2] - 1.6) < 1e-9)
        #expect(abs(s[1] - s[3]) < 1e-9)
        #expect(s[1] < s[2] && s[1] > 1)
        #expect(s[0] == 1 && s[4] == 1)
    }

    @Test("Verschiebung: Nachbarn weichen aus, Summe bleibt zentriert")
    func shifts() {
        let base = 52.0
        let s = Magnification.scales(pointerX: 146, centers: centers, maxScale: 1.6, reach: 150)
        let r = Magnification.shifts(scales: s, base: base)
        #expect(abs(r.extra - s.map { ($0 - 1) * base }.reduce(0, +)) < 1e-9)
        #expect(r.shifts[0] < 0 && r.shifts[4] > 0)
        #expect(abs(r.shifts[0] + r.shifts[4]) < 1e-9)
        #expect(abs(r.shifts[2]) < 1e-9)
        let rest = Magnification.shifts(scales: [1, 1, 1], base: base)
        #expect(rest.shifts == [0, 0, 0] && rest.extra == 0)
    }
}
