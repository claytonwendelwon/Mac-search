import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey using the Carbon Hot Key API.
/// This works without Accessibility permissions and fires even when Beacon
/// is not the frontmost app.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    /// `noErr` if registration succeeded; otherwise the failing OSStatus.
    private(set) var registrationStatus: OSStatus = noErr
    var isRegistered: Bool { registrationStatus == noErr && hotKeyRef != nil }

    // A unique signature/id so the dispatcher can route events back to us.
    private static let signature: OSType = {
        let chars = Array("BCON".utf8)
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()
    private let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: 1)

    /// - Parameters:
    ///   - keyCode: A Carbon virtual key code (e.g. `kVK_Space`).
    ///   - modifiers: Carbon modifier flags (e.g. `optionKey`).
    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        installEventHandler()
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // Pass an unretained pointer to self so the C callback can call back in.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var firedID = EventHotKeyID()
            let status = GetEventParameter(eventRef,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &firedID)
            guard status == noErr else { return status }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            if firedID.signature == hotKey.hotKeyID.signature && firedID.id == hotKey.hotKeyID.id {
                DispatchQueue.main.async { hotKey.handler() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        registrationStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        if registrationStatus != noErr {
            print("[Beacon] RegisterEventHotKey failed with status \(registrationStatus)")
        }
    }
}
