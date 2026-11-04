import Foundation
import Testing
@testable import NeoDockKit

@Suite struct FileMemoTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "filememo-\(UUID().uuidString).txt")

    @Test func unveraenderteDateiWirdNichtNeuBerechnet() throws {
        try Data("a".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let memo = FileMemo<Int>()
        var runs = 0
        for _ in 0..<3 { _ = memo.value(for: url) { runs += 1; return runs } }
        #expect(runs == 1)
    }

    @Test func angehaengteZeileRechnetNeu() throws {
        try Data("a".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let memo = FileMemo<Int>()
        _ = memo.value(for: url) { 1 }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("b".utf8))
        try handle.close()
        #expect(memo.value(for: url) { 2 } == 2)
    }

    @Test func gleicheGroesseMitNeuerZeitRechnetNeu() throws {
        try Data("a".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let memo = FileMemo<Int>()
        _ = memo.value(for: url) { 1 }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: url.path)
        #expect(memo.value(for: url) { 2 } == 2)
    }

    @Test func fehlendeDateiWirdNichtGemerkt() {
        let memo = FileMemo<Int>()
        #expect(memo.value(for: url) { 1 } == 1)
        #expect(memo.value(for: url) { 2 } == 2)
    }
}
