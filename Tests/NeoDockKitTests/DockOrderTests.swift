import Testing
@testable import NeoDockKit

@Suite struct DockOrderTests {
    let finder = "F"
    let pinned = ["A", "B", "C", "D"]
    var visible: [String] { [finder] + pinned + ["R"] }   // R läuft, ist nicht angeheftet

    @Test("nach links ziehen: vor das Ziel")
    func left() {
        #expect(DockOrder.moving("D", toward: "B", pinned: pinned, visible: visible, fixedFirst: finder) == ["A", "D", "B", "C"])
    }

    @Test("nach rechts ziehen: hinter das Ziel — auch ans Ende")
    func right() {
        #expect(DockOrder.moving("A", toward: "C", pinned: pinned, visible: visible, fixedFirst: finder) == ["B", "C", "A", "D"])
        #expect(DockOrder.moving("A", toward: "D", pinned: pinned, visible: visible, fixedFirst: finder) == ["B", "C", "D", "A"])
    }

    @Test("laufende, nicht angeheftete App in die Reihe ziehen heftet sie an")
    func pinsRunning() {
        #expect(DockOrder.moving("R", toward: "B", pinned: pinned, visible: visible, fixedFirst: finder) == ["A", "R", "B", "C", "D"])
    }

    @Test("Finder bleibt vorn und lässt sich nicht verschieben")
    func finderFixed() {
        #expect(DockOrder.moving("C", toward: finder, pinned: pinned, visible: visible, fixedFirst: finder) == ["C", "A", "B", "D"])
        #expect(DockOrder.moving(finder, toward: "C", pinned: pinned, visible: visible, fixedFirst: finder) == pinned)
    }

    @Test("aus dem Finder anheften: vor dem Ziel oder am Ende, ohne Doppel")
    func inserting() {
        #expect(DockOrder.inserting("X", before: "B", pinned: pinned) == ["A", "X", "B", "C", "D"])
        #expect(DockOrder.inserting("X", before: nil, pinned: pinned) == ["A", "B", "C", "D", "X"])
        #expect(DockOrder.inserting("C", before: "A", pinned: pinned) == ["C", "A", "B", "D"])
    }
}
