import Carbon.HIToolbox

/// Carbon 全局热键注册（默认 ⌥⌘H 呼出/收起面板）
final class HotKeyCenter {

    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handlerBox: HandlerBox?

    private final class HandlerBox {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
    }

    private init() {}

    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        unregister()

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let box = HandlerBox(handler)
        handlerBox = box
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()

        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let box = Unmanaged<HotKeyCenter.HandlerBox>
                    .fromOpaque(userData).takeUnretainedValue()
                box.handler()
                return noErr
            },
            1,
            &spec,
            boxPtr,
            &handlerRef
        )
        if status == noErr { eventHandler = handlerRef }

        var hkRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D48_4F4D) /* 'MHOM' */, id: 1)
        RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hkRef
        )
        hotKeyRef = hkRef
    }

    func unregister() {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
            hotKeyRef = nil
        }
        if let eh = eventHandler {
            RemoveEventHandler(eh)
            eventHandler = nil
        }
        handlerBox = nil
    }
}
