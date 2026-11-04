import CoreGraphics
import Testing
@testable import NeoDockKit

@Suite struct DockAreaTests {
    let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    @Test func flaecheLiegtUntenInDerMitte() {
        #expect(DockArea.reserved(screen: screen, length: 2000, depth: 84) == CGRect(x: 280, y: 1356, width: 2000, height: 84))
    }

    @Test func freiBelegtNichts() {
        #expect(DockArea.free(screen: screen) == CGRect(x: 0, y: 1440, width: 2560, height: 0))
    }

    @Test func fensterHinterDerLeisteWirdGekuerzt() {
        let area = DockArea.reserved(screen: screen, length: 2000, depth: 84)
        #expect(DockArea.fitted(CGRect(x: 10, y: 30, width: 1900, height: 1410), above: area, minimum: 200)
            == CGRect(x: 10, y: 30, width: 1900, height: 1326))
    }

    @Test func fensterNebenEinerSchmalenLeisteZaehltAuch() {
        let area = DockArea.reserved(screen: screen, length: 500, depth: 84)
        #expect(DockArea.fitted(CGRect(x: 0, y: 100, width: 300, height: 1340), above: area, minimum: 200)?.height == 1256)
    }

    @Test func fensterDarueberBleibt() {
        let area = DockArea.reserved(screen: screen, length: 2000, depth: 84)
        #expect(DockArea.fitted(CGRect(x: 10, y: 30, width: 800, height: 600), above: area, minimum: 200) == nil)
    }

    @Test func zuKleinerRestBleibtWieEsIst() {
        let area = DockArea.reserved(screen: screen, length: 2000, depth: 84)
        #expect(DockArea.fitted(CGRect(x: 10, y: 1300, width: 800, height: 140), above: area, minimum: 200) == nil)
    }
}
