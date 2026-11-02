import AppKit
import AudioToolbox
import CoreAudio
import IOKit.pwr_mgt
import Observation

/// Lautstärke und Stummschaltung der Standardausgabe (CoreAudio).
@Observable
final class VolumeService {
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private(set) var isAvailable = false
    @ObservationIgnored private var task: Task<Void, Never>?
    static let refresh: Duration = .seconds(2)

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.read()
                try? await Task.sleep(for: Self.refresh)
            }
        }
    }

    func read() {
        guard let device = Self.outputDevice() else { isAvailable = false; return }
        let v: Float32? = Self.get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        let m: UInt32? = Self.get(device, kAudioDevicePropertyMute)
        isAvailable = v != nil
        if let v, v != volume { volume = v }
        let muted = (m ?? 0) != 0
        if muted != isMuted { isMuted = muted }
    }

    func setVolume(_ value: Float) {
        guard let device = Self.outputDevice() else { return }
        let v = Float32(min(max(value, 0), 1))
        if Self.set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, v) { volume = v }
        if isMuted, v > 0 { toggleMute() }
    }

    func toggleMute() {
        guard let device = Self.outputDevice() else { return }
        let m: UInt32 = isMuted ? 0 : 1
        if Self.set(device, kAudioDevicePropertyMute, m) { isMuted = m != 0 }
    }

    private static func outputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: BitwiseCopyable>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func set<T: BitwiseCopyable>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: T) -> Bool {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        return withUnsafeBytes(of: value) { raw in
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(raw.count), raw.baseAddress!) == noErr
        }
    }
}

/// Verhindert, dass der Bildschirm einschläft, solange eingeschaltet (wie caffeinate -d).
@Observable
final class KeepAwakeService {
    private(set) var isOn = false
    @ObservationIgnored private var assertion: IOPMAssertionID = 0

    func toggle() {
        if isOn {
            IOPMAssertionRelease(assertion)
            isOn = false
        } else {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "NeoDock: Wach halten" as CFString, &assertion)
            isOn = result == kIOReturnSuccess
        }
    }
}

enum StorageReader {
    struct Status: Equatable { let available: Int64; let total: Int64 }

    static func read() -> Status? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(filePath: NSHomeDirectory()).resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return Status(available: available, total: Int64(total))
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
    }
}
