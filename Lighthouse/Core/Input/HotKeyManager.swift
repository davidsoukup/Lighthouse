import Foundation
import Carbon

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4C484B59), id: 1) // "LHKY"
    static var sharedHandler: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister()
        Self.sharedHandler = handler

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))

        handlerRef = nil
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &eventSpec,
                            nil, &handlerRef)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    func registerCommandSpace(handler: @escaping () -> Void) {
        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), handler: handler)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        Self.sharedHandler = nil
    }
}

private func hotKeyHandler(_ nextHandler: EventHandlerCallRef?,
                           _ theEvent: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hkID = EventHotKeyID()
    GetEventParameter(theEvent, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    if hkID.signature == OSType(0x4C484B59) && hkID.id == 1 {
        HotKeyManager.sharedHandler?()
    }
    return noErr
}
