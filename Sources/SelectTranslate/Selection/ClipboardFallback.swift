import AppKit

/// 兜底方案：模拟 ⌘C 复制选区，读到内容后还原用户原来的剪贴板
enum ClipboardFallback {

    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    static func copySelection() -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = capture(pasteboard)
        let changeCountBefore = pasteboard.changeCount

        sendCopyKeystroke()

        var copied: String?
        let deadline = Date().addingTimeInterval(0.45)
        while Date() < deadline {
            if pasteboard.changeCount != changeCountBefore {
                copied = pasteboard.string(forType: .string)
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        restore(snapshot, to: pasteboard)
        return copied
    }

    private static func capture(_ pasteboard: NSPasteboard) -> Snapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
        return Snapshot(items: items)
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func sendCopyKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 0x08
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(2000)
        up.post(tap: .cghidEventTap)
    }
}