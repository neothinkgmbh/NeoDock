import AppKit
import NeoDockKit
import Observation

/// Apps, die gerade Aufmerksamkeit wollen (`NSApp.requestUserAttention`). Die Anfrage geht ans
/// macOS-Dock, LaunchServices führt sie aber als Wert `LSWantsAttention` mit. `lsappinfo listen`
/// läuft als Kindprozess und ist nur der Wecker: Der Stand wird jedes Mal neu erfragt, so gibt es
/// keinen eigenen Zustand, der nach einem verpassten Ereignis falsch bleibt. Stürzt NeoDock ab,
/// endet das Kind beim nächsten Ereignis von selbst (SIGPIPE, gemessen).
@Observable
final class AttentionMonitor {
    /// App-Pfade (wie `DockApp.key`).
    private(set) var keys: Set<String> = []
    @ObservationIgnored private var listener: Process?
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false
    nonisolated private static let tool = URL(filePath: "/usr/bin/lsappinfo")
    private static let restartDelay: Duration = .seconds(5)

    func start() {
        listen()
        refresh()
    }

    func stop() {
        isStopped = true
        listener?.terminate()
    }

    private func listen() {
        let process = Process()
        let output = Pipe()
        process.executableURL = Self.tool
        process.arguments = ["listen", "+kLSNotifyApplicationWantsAttentionChanged", "forever"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard !handle.availableData.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in self?.refresh() }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.listenerEnded() }
        }
        do {
            try process.run()
            listener = process
        } catch {
            NSLog("NeoDock: lsappinfo nicht startbar, Icons hüpfen nicht bei Anfragen: \(error)")
        }
    }

    private func listenerEnded() {
        listener = nil
        guard !isStopped else { return }
        NSLog("NeoDock: lsappinfo beendet, Neustart in Kürze")
        Task { [weak self] in
            try? await Task.sleep(for: Self.restartDelay)
            guard let self, !self.isStopped else { return }
            self.start()
        }
    }

    /// Abfragen laufen nacheinander: Kommt währenddessen ein Ereignis, folgt genau eine weitere.
    private func refresh() {
        guard !isRefreshing else {
            needsRefresh = true
            return
        }
        isRefreshing = true
        Task {
            repeat {
                needsRefresh = false
                let pids = await Task.detached(priority: .utility) { Self.wantingPIDs() }.value
                let fresh = Set(pids.compactMap { NSRunningApplication(processIdentifier: $0)?.bundleURL.map(AppsProvider.key) })
                if keys != fresh { keys = fresh }
            } while needsRefresh
            isRefreshing = false
        }
    }

    nonisolated private static func wantingPIDs() -> [pid_t] {
        LSAppInfo.asns(inFindOutput: run(["find", "LSWantsAttention=true"]))
            .compactMap { LSAppInfo.pid(inInfoOutput: run(["info", "-only", "pid", $0])) }
    }

    nonisolated private static func run(_ arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("NeoDock: lsappinfo-Abfrage fehlgeschlagen: \(error)")
            return ""
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
