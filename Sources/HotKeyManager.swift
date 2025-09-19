import Foundation
import Carbon

final class HotKeyManager {
    private let keyCode: UInt32
    private let modifiers: [UInt32]
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: [UInt32], handler: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func register() {
        unregister()

        let modifierFlags = modifiers.reduce(UInt32(0)) { partialResult, flag in
            partialResult | flag
        }

        var hotKeyRef: EventHotKeyRef?
        let signature: OSType = 0x4C425231 // 'LBR1'
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifierFlags, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, let unwrappedHotKeyRef = hotKeyRef else {
            return
        }
        self.hotKeyRef = unwrappedHotKeyRef

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let unmanaged = Unmanaged<HotKeyManager>.fromOpaque(userData)
            unmanaged.takeUnretainedValue().handler()
            return noErr
        }

        let statusHandler = InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandlerRef)
        if statusHandler != noErr {
            unregister()
        }
    }

    func unregister() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        unregister()
    }
}
