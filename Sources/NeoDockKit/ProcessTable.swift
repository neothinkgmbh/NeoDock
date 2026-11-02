import Darwin
import Foundation

/// Prozessabfragen über sysctl und libproc — ohne AppKit, damit Quellen und Tests sie nutzen können.
public enum ProcessTable {
    static let pathBufferSize = 4096
    /// dev_t ohne Terminal (NODEV).
    static let noDevice: dev_t = -1

    static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        guard let ppid = kinfo(pid)?.kp_eproc.e_ppid, ppid > 1 else { return nil }
        return ppid
    }

    public static func startTime(of pid: pid_t) -> Date? {
        guard let start = kinfo(pid)?.kp_proc.p_starttime else { return nil }
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    /// Hängt der Prozess an einem Terminal? Server und Hintergrunddienste nicht.
    public static func hasTerminal(_ pid: pid_t) -> Bool {
        guard let device = kinfo(pid)?.kp_eproc.e_tdev else { return false }
        return device != noDevice
    }

    public static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    public static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: pathBufferSize)
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    public static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(filled, 0))))
    }

    /// Laufende Codex-CLI-Prozesse an einem Terminal (nicht die Server der Codex-App oder VS Code).
    public static func codexCLIs() -> [(pid: pid_t, cwd: String?)] {
        allPIDs().compactMap { pid in
            guard let path = executablePath(of: pid),
                  URL(filePath: path).lastPathComponent == "codex",
                  !path.contains(".app/"), hasTerminal(pid) else { return nil }
            return (pid, workingDirectory(of: pid))
        }
    }
}
