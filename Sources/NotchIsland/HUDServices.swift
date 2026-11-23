import AppKit
import ApplicationServices
import AudioToolbox
import CoreAudio

// MARK: - Volume (CoreAudio)

final class VolumeController: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    /// Fired when volume/mute changes (not when the output device switches).
    var onChange: (() -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var volumeAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var muteAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var defaultDeviceAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private lazy var valueListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.valuesChanged() }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddr, .main, deviceListener)
        attach()
    }

    private func attach() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddr, .main, valueListener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddr, .main, valueListener)
        }
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddr, 0, nil, &size, &id)
        device = id
        AudioObjectAddPropertyListenerBlock(device, &volumeAddr, .main, valueListener)
        AudioObjectAddPropertyListenerBlock(device, &muteAddr, .main, valueListener)
        read()
    }

    private func read() {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &volumeAddr, 0, nil, &size, &v) == noErr { volume = v }
        var m = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        muted = AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &size, &m) == noErr && m != 0
    }

    private func valuesChanged() {
        let (oldVolume, oldMuted) = (volume, muted)
        read()
        if abs(oldVolume - volume) > 0.001 || oldMuted != muted { onChange?() }
    }

    var canSetVolume: Bool {
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &volumeAddr, &settable) == noErr && settable.boolValue
    }

    func setVolume(_ v: Float) {
        var value = Float32(min(max(v, 0), 1))
        AudioObjectSetPropertyData(device, &volumeAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        volume = value
        if muted && value > 0 { setMuted(false) }
    }

    func setMuted(_ m: Bool) {
        var value = UInt32(m ? 1 : 0)
        AudioObjectSetPropertyData(device, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        muted = m
    }

    func toggleMute() { setMuted(!muted) }

    /// Matches the system: 16 steps, or 64 with ⌥⇧.
    func step(up: Bool, fine: Bool) {
        let s: Float = fine ? 1 / 64 : 1 / 16
        let current = muted && up ? 0 : volume
        setVolume(((current / s).rounded() + (up ? 1 : -1)) * s)
    }
}

// MARK: - Brightness (private DisplayServices framework)

final class BrightnessController: ObservableObject {
    @Published private(set) var level: Float = 0
    var onChange: (() -> Void)?

    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private let getFn: GetFn?
    private let setFn: SetFn?
    private var displayID: CGDirectDisplayID = CGMainDisplayID()
    private var timer: Timer?

    var canSet: Bool { setFn != nil && read() != nil }

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
        resolveDisplay()
        level = read() ?? 0
        // There's no public change notification, so poll cheaply (~100µs per read).
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func resolveDisplay() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        displayID = ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    private func read() -> Float? {
        guard let getFn else { return nil }
        var b: Float = 0
        return getFn(displayID, &b) == 0 ? b : nil
    }

    private func poll() {
        guard let b = read() else { resolveDisplay(); return }
        let delta = abs(b - level)
        guard delta > 0.0005 else { return }
        level = b
        // Brightness keys move in ~6% steps; ignore slow auto-brightness drift.
        if delta >= 0.03 { onChange?() }
    }

    func step(up: Bool, fine: Bool) {
        guard let setFn else { return }
        let s: Float = fine ? 1 / 64 : 1 / 16
        let current = read() ?? level
        let target = min(max(((current / s).rounded() + (up ? 1 : -1)) * s, 0), 1)
        _ = setFn(displayID, target)
        level = target
    }
}

// MARK: - Media key interception (to replace the system HUD)

final class MediaKeyTap {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    /// Return true if the key was handled (it is then swallowed so the system HUD doesn't appear).
    var handler: ((_ key: Key, _ fine: Bool, _ isDown: Bool, _ isRepeat: Bool) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.isTrusted else { return false }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.type == .systemDefined,
              ns.subtype.rawValue == 8 else { return pass }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        let flags = ns.data1 & 0xFFFF
        let isDown = (flags & 0xFF00) >> 8 == 0xA
        let isRepeat = flags & 0x1 == 1
        let key: Key
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        default: return pass
        }
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
        return handler?(key, fine, isDown, isRepeat) == true ? nil : pass
    }
}
