import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's `RegisterEventHotKey`, which — unlike an
/// `NSEvent` global monitor — needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    private init() {}

    func register(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        handlers[id] = action
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x534B_5242), id: id) // 'SKRB'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr { refs.append(ref) }
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.fire(id: hotKeyID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}

enum HotKey {
    static let toggleOverlay: UInt32 = 1
    static let clearAnnotations: UInt32 = 2
    static let clickThrough: UInt32 = 3

    /// ⌃⌥⌘ — unlikely to collide with anything an app already claims.
    static let modifiers = controlKey | optionKey | cmdKey
}
