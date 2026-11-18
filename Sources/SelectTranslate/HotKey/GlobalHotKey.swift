import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，不需要辅助功能权限也能注册）
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var hotKeyIDValue: UInt32 = 0

    private static let signature: OSType = 0x53454C54 // 'SELT'

    /// id 用来区分同一个 App 里注册的多个快捷键；不传就是 1（保持旧行为）
    func register(
        id: UInt32 = 1,
        keyCode: UInt32,
        carbonModifiers: UInt32,
        action: @escaping () -> Void
    ) {
        unregister()
        self.action = action
        hotKeyIDValue = id

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            NSLog("[SelectTranslate] 快捷键注册失败（id=\(id)）：\(registerStatus)")
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

                // 同一个 App 的所有 handler 都会收到事件，必须按 id 过滤，
                // 否则按一个快捷键会触发所有快捷键的动作。
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard status == noErr,
                      pressed.signature == GlobalHotKey.signature,
                      pressed.id == hotKey.hotKeyIDValue else { return noErr }

                DispatchQueue.main.async { hotKey.action?() }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
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
    }

    deinit { unregister() }
}